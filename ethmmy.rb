require './helpers.rb'

module EthmmyAgent
	class Client

		include EthmmyHelpers

		attr_reader :subscriptions, :username

		def initialize(username, password)
			@username = username
			@password = password
			@base_url = 'https://alexander.ee.auth.gr:8443/eTHMMY/'
			@callbacks = Hash.new { |h, k| h[k] = [] }

			$session_year 	= Time.now.year.to_i
			$session_month 	= Time.now.month.to_i
			$session_day 	= Time.now.day.to_i
			$session_hour 	= Time.now.hour.to_i
			$session_minute = Time.now.min.to_i

			#cert_store = OpenSSL::X509::Store.new
			#cert_store.set_default_paths
			#cert_store.add_file File.expand_path('./cacert.pem')

			@agent = Mechanize.new { |agent|
				  #agent.user_agent_alias = 'Mac Safari'
				  #agent.cert_store = cert_store
				  #agent.ssl_version='SSLv3'
				  agent.verify_mode= OpenSSL::SSL::VERIFY_NONE
				  #agent.agent.http.ca_file = File.expand_path('./cacert.pem')
			}
		end

		def login
			login_slug = 'loginAction.do'
			begin
				login = @agent.post(
					@base_url + login_slug, {
					:username => @username,
					:password => @password
					}
				)
				unless login.search('logout.do')
					raise "Unable to login"
				end
			rescue Exception => e
				puts e.message
			end
			@courses = get_all_courses
		end

		def logout
			logout_slug = 'logout.do'
			@agent.get @base_url + logout_slug
		end

		def get_courses_by_semester(semester)
			courses = {}
			year = (semester + 1) / 2
			season = semester - (year - 1)*2
			courses_slug = 'cms.course.data.do?method=jsplist&PRMID='
			
			if @username == 'guest'
				anchor_child = 1
			else
				anchor_child = 3
			end

			@agent.get(@base_url + courses_slug + year.to_s) do |year_page|
				year_page.search("table.etDivTitleCont")[season - 1].parent.search('table').each do |entry|
					course = entry.search('p.listLabel')
					title = course.search("a:nth-child(#{anchor_child})").text
					ethmmy_id = course.search("a:nth-child(#{anchor_child}) @href").text.match(/\d+$/).to_s.to_i
					courses[ethmmy_id] = title unless title.empty?
				end
			end
			return courses
		end

		def get_courses_by_year(year)
			return get_courses_by_semester(year*2-1).merge get_courses_by_semester(year*2)
		end

		def get_all_courses
			courses = {}
			1.upto 10 do |semester|
				courses.merge! get_courses_by_semester(semester)
			end
			return courses
		end

		def get_subscriptions
			subscriptions = []
			home_slug = 'home.do'
			unless @username == 'guest'
				@agent.get(@base_url + home_slug) do |home_page|
					sidebar = home_page.search(".//img[@src=\"images/books.gif\"]")
					sidebar.each do |course|
						subscriptions << course.parent['href'].match(/\d+$/).to_s.to_i
					end
				end
			end
			return subscriptions
		end

		def get_latest_announcement_by(id)
			announcement = nil
			course_login_to id
			announcements_slug = 'cms.announcement.data.do?method=jsplist&PRMID='
			begin
				@agent.get(@base_url + announcements_slug + id.to_s) do |announcements_page|
					announcement = announcements_page.search('p.listLabel').first
					error = announcements_page.search(".//img[@src=\"images/icon_warning_32x32.gif\"]").first
					if error
						raise "Disconnected"
					end
				end
			rescue Exception => e
				@callbacks[:debug_message].each {|c| c.call *(e.message)}
			end
			return ethmmy_sanitize announcement.parent unless announcement.nil?
		end

		def check_for_new_announcement_by(id)
			announcement_array = get_latest_announcement_by id
			subject = @courses[id]
			announcement = announcement_array[0]
			ethmmy_date = announcement_array[1][:date].split(' ')

			day = ethmmy_date[$ethmmy_date_format["day"]].to_i
			month = $greek_months_map[ethmmy_date[$ethmmy_date_format["month"]]].to_i
			year = ethmmy_date[$ethmmy_date_format["year"]].to_i
			time = ethmmy_date[$ethmmy_date_format["time"]]
			hour = time.split(':')[0].to_i + $greek_meridian_map[ethmmy_date[$ethmmy_date_format["meridian"]]].to_i
			if hour == 24 then hour = 0	end
			minute = time.split(':')[1].to_i
			if (year > $session_year)
				@callbacks[:new_announcement].each {|c| c.call *([subject,announcement])}
			elsif (year == $session_year) && (month > $session_month)
				@callbacks[:new_announcement].each {|c| c.call *([subject,announcement])}
			elsif (year == $session_year) && (month == $session_month) && day > $session_day
				@callbacks[:new_announcement].each {|c| c.call *([subject,announcement])}
			elsif (year == $session_year) && (month == $session_month) && (day == $session_day)
				if hour > $session_hour || ((hour == $session_hour) && (minute >= $session_minute))
					@callbacks[:new_announcement].each {|c| c.call *([subject,announcement])}
				end
			end

			return [announcement_array[1][:title],day,month,year,hour,minute]
		end

		def poll_announcements(subscriptions)
			debug_year 		= $session_year
			debug_month		= $session_month
			debug_day 		= $session_day
			debug_hour		= $session_hour
			debug_minute 	= $session_minute
			debug_message 	= {}
			while true do
				subscriptions.each do |s|
					debug_time = "#{debug_day}/#{debug_month}/#{debug_year} #{debug_hour}:#{debug_minute}"
					debug_message = check_for_new_announcement_by s
					formated_message = "||#{debug_time}|| On #{debug_message[1]}/#{debug_message[2]}/#{debug_message[3]} #{debug_message[4]}:#{debug_message[5]} => #{debug_message[0]}"
					@callbacks[:debug_message].each {|c| c.call *(formated_message)}
				end
				$session_year 	= Time.now.year.to_i
				$session_month 	= Time.now.month.to_i
				$session_day 	= Time.now.day.to_i
				$session_hour 	= Time.now.hour.to_i
				$session_minute = Time.now.min.to_i
				@callbacks[:debug_message].each {|c| c.call *(debug_message)}
				sleep($ethmmy_poll_interval)
			end
		end

		def spawn_announcement_poller(subscriptions)
			spawn_thread(:poll_announcements,subscriptions)
		end

		def get_all_announcements_by(id)
			announcements = []
			course_login_to id
			announcements_slug = 'cms.announcement.data.do?method=jsplist&PRMID='
			@agent.get(@base_url + announcements_slug + id.to_s) do |announcements_page|
				announcements_board = announcements_page.search('p.listLabel').map(&:parent)
				unless announcements_board.nil?
					announcements_board.each do |announcement|
						announcements << ethmmy_sanitize(announcement)[1]
					end
				end
			end
			return announcements
		end

		def get_all_subscription_announcements
			announcements = {}
			@subscriptions.each do |id|
				p id
				announcements[id] = get_all_announcements_by id
			end
			return announcements
		end

		def subscribe_to(id)
			subscribe_slug = 'cms.course.data.do?method=jspregister&PRMID='
			@agent.get(@base_url + subscribe_slug + id.to_s)
		end

		def subscribe_to!(id)
			subscribe_to id
			@subscriptions << id
			#@subscriptions.sort!
		end

		def unsubscribe_from(id)
			unsuscribe_slug = 'cms.course.data.do?method=jspunregister&PRMID='
			@agent.get(@base_url + unsuscribe_slug + id.to_s)
		end

		def unsubscribe_from!(id)
			unsubscribe_from id
			@subscriptions.delete id
		end

		def course_login_to(id)
			course_login_slug = 'cms.course.login.do?method=execute&PRMID='
			@agent.get(@base_url + course_login_slug + id.to_s)
		end

		define_method "on_new_announcement" do |&block|
			@callbacks[:new_announcement] << block
		end
		define_method "on_debug_message" do |&block|
			@callbacks[:debug_message] << block
		end
	end
end
