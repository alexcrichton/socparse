require 'em-http-request'
require 'mysql2'

client = Mysql2::Client.new(:host => 'localhost', :username => 'root',
                            :database => 'socdump')

season, year = ARGV[0], ARGV[1]
if season.nil? || year.nil?
  puts "usage: #{$0} <season> <year>"
  exit 1
end


pattern = 'https://enr-apps.as.cmu.edu/open/SOC/SOCServlet?CourseNo=%s&SEMESTER=%s&Formname=Course_Detail'
semester = season[0,1] + (year.to_i % 100).to_s

data = {}

def update cur, total
  width = 80
  pctg = cur.to_f / total
  amt = width * pctg
  print "\r" + ('=' * (amt - 1)) + '>' + (' ' * (width - amt + 1))
  printf "%.2f%%   ", pctg * 100
end

EM.run do
  row = client.query("SELECT id FROM semesters WHERE year = #{year} AND
                                                     season = '#{season}'")
  sem_id = row.first['id']
  if sem_id.nil?
    puts "Couldn't find semester..."
    exit 2
  end

  query = "SELECT id, number FROM courses WHERE semester_id = #{sem_id}"
  rows = client.query(query)

  todo = rows.to_a
  max  = todo.size
  done = 0

  EM::Iterator.new(rows, 50).each proc { |row, iter|
    http = EM::HttpRequest.new(pattern % [row['number'], semester]).get
    http.callback {
      data[row['number']] = http.response
      done += 1
      update done, max
      iter.next
    }
    http.errback {
      data[row['number']] = :error
      update done, max
      done += 1
      iter.next
    }
  }, proc { EM.stop }
end

File.open('cache-course-info', 'wb') { |f| f << Marshal.dump(data) }
