require 'mysql2'
require 'nokogiri'

client = Mysql2::Client.new(:host => 'localhost', :username => 'root',
                            :database => 'socdump')

season, year = ARGV[0], ARGV[1]
if season.nil? || year.nil?
  puts "usage: #{$0} <season> <year>"
  exit 1
end

data = Marshal.load(File.open('cache-course-info', 'rb') { |f| f.read })

def update cur, total
  width = 80
  pctg = cur.to_f / total
  amt = width * pctg
  print "\r" + ('=' * (amt - 1)) + '>' + (' ' * (width - amt + 1))
  printf "%.2f%%   ", pctg * 100
end

row = client.query("SELECT id FROM semesters WHERE year = #{year} AND
                                                   season = '#{season}'")
if row.first.nil? || row.first['id'].nil?
  puts "Couldn't find semester..."
  exit 2
end
sem_id = row.first['id']

data.each do |number, response|
  doc = Nokogiri::HTML(response.to_s)
  match = doc.text.match /description:(.*)prerequisites:/im
  if match
    escaped = client.escape(match[1].strip)
    query = "UPDATE courses SET description = '#{escaped}' WHERE semester_id = #{sem_id} AND number = '#{number}'"
    client.query(query)

  else
    puts "Bad response for: #{number}, skipping..."
  end
end
