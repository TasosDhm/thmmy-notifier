require 'mechanize'

module EthmmyAgent
	module EthmmyHelpers
		Announcement = Struct.new(:title, :date, :author, :body)

		$ethmmy_poll_interval = 10*60

		$css = '
			<style type="text/css">
			.listLabel {
				FONT: bold 11px Verdana; COLOR: #6487db
			}
			P {
				MARGIN: 0em; FONT: 11px Verdana
			}
			</style>'

		$ethmmy_date_format = {	"day"		=> 0,
								"month"		=> 1,
								"year"		=> 2,
								"time"		=> 3,
								"meridian"	=> 4
		}

		$greek_months_map = { 	"Ιαν"	=> 1,
								"Φεβ"	=> 2,
								"Μαρ"	=> 3,
								"Απρ"	=> 4,
								"Μαϊ"	=> 5,
								"Ιουν"	=> 6,
								"Ιουλ"	=> 7,
								"Αυγ"	=> 8,
								"Σεπ"	=> 9,
								"Οκτ"	=> 10,
								"Νοε"	=> 11,
								"Δεκ"	=> 12
		}

		$greek_meridian_map = { "πμ"	=> 0,
								"μμ"	=> 12

		}

		$session_year 	= Time.now.year.to_i
		$session_month 	= Time.now.month.to_i
		$session_day 	= Time.now.day.to_i
		$session_hour 	= Time.now.hour.to_i
		$session_minute = Time.now.min.to_i

		def ethmmy_sanitize(announcement)
			
			polished_html = $css + announcement.to_html(:encoding => 'UTF-8').gsub(/&amp;nbsp/,'')

			arr = announcement.search('p')
			title = arr[0].text.scan(/[^\r\n\t]/).join.lstrip
			date = arr[1].search('b').text.scan(/[^\r\n\t]/).join.lstrip
			author = arr[1].search('i').text.scan(/[^\r\n\t]/).join.lstrip

			announcement.search('p.listLabel').remove
			announcement.search('p > b').remove
			announcement.search('p > i').remove
			body = announcement.to_html(:encoding => 'UTF-8').gsub('&amp;', '&')

			structured_ann = Announcement.new(title, date, author, body)

			return [polished_html, structured_ann]
		end
	end

	module ThreadTools
		class DuplicateThread < StandardError; end

		protected
		def spawn_thread(sym,arg)
			raise DuplicateThread if threads.has_key? sym
			threads[sym] = Thread.new {send sym,arg}
		end

		def threads
			@threads ||= {}
		end
	end
end