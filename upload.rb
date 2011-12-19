require 'mysql2'
require 'logger'
SECTION = 0
LECTURE = 1

class Hash
  def slice *keys
    keys = keys.flatten
    select{ |k, _| keys.include?(k) }
  end
end

@log = Logger.new STDOUT
@log.level = Logger::INFO

semesters = Marshal.load(File.open('cache', 'rb'){ |f| f.read })
db_name = 'socdump'

# See http://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/MysqlAdapter.html
# for options here
client = Mysql2::Client.new(:host => 'localhost', :username => 'root')
client.query("DROP DATABASE #{db_name}")
client.query("CREATE DATABASE IF NOT EXISTS #{db_name}")
client.query("USE #{db_name}")

# Create tables
client.query('CREATE TABLE IF NOT EXISTS semesters
              (id INT(31) PRIMARY KEY AUTO_INCREMENT, season VARCHAR(255),
               year INT(31))')
client.query('CREATE TABLE IF NOT EXISTS departments
              (id INT(31) PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255))')
client.query('CREATE TABLE IF NOT EXISTS courses
              (id INT(31) PRIMARY KEY AUTO_INCREMENT, number VARCHAR(255),
               name VARCHAR(255), units VARCHAR(255), department_id INT(31),
               semester_id INT(31), deleted INT(31),
               INDEX dpt_idx USING HASH (department_id ASC),
               INDEX sem_idx USING HASH (semester_id ASC))')
client.query('CREATE TABLE IF NOT EXISTS meetings
              (id INT(31) PRIMARY KEY AUTO_INCREMENT, type INT(31),
               course_id INT(31), section VARCHAR(255),
               begin VARCHAR(255), end VARCHAR(255), days VARCHAR(255),
               instructor VARCHAR(255), deleted INT(31),
               INDEX c_idx USING HASH (course_id ASC))')

def cast client, value
  if value.is_a?(String)
    "'" + client.escape(value) + "'"
  else
    value.to_s
  end
end

def find client, table, attrs
  escaped = attrs.map{ |k, v| [k, cast(client, v)] }
  query = escaped.map{ |k, v| "#{k} = #{v}" }.join(' AND ')
  query = "SELECT id FROM #{table} WHERE #{query}"
  @log.debug query
  row = client.query(query)
  if row.size == 0
    keys = escaped.map{ |k, _| k }
    values = escaped.map{ |_, v| v }
    query = "INSERT INTO #{table} (#{keys.join(', ')}) VALUES (#{values.join(', ')})"
    @log.debug query
    client.query(query)
    client.last_id
  else
    row.first['id']
  end
end

def update cur, total
  return unless @log.level == Logger::INFO
  width = 80
  pctg = cur.to_f / total
  amt = width * pctg
  print "\r" + ('=' * (amt - 1)) + '>' + (' ' * (width - amt + 1))
  printf "%.2f%%   ", pctg * 100
end

semesters.each do |sem|
  sem_id = find client, 'semesters', sem.slice(:season, :year)
  ids = client.query("SELECT id FROM courses WHERE semester_id=#{sem_id}")
  ids = ids.map{ |h| h['id'] }
  @log.info "Updating semester: #{sem_id}"

  cur = 0
  max = sem[:departments].inject(0) { |sum, (_, courses)| sum + courses.size }

  sem[:departments].each do |dptmt, courses|
    dpt_id = find client, 'departments', :name => dptmt
    @log.debug "Updating department: #{dptmt}"

    courses.each do |num, course|
      id = find client, 'courses', :semester_id => sem_id,
                                   :number => num
      ids.delete id
      query = "UPDATE courses SET name = '#{client.escape course[:title]}',
                                  units = '#{client.escape course[:units]}',
                                  department_id = #{dpt_id},
                                  deleted = 0
                              WHERE id = #{id}".gsub(/\n\s*/, " ")
      @log.debug query
      client.query query

      meets = client.query("SELECT id FROM meetings WHERE course_id=#{id}")
      meets = meets.map{ |h| h['id'] }
      
      update = lambda { |arr, type|
        arr.each do |meet|
          opts = meet.slice(:begin, :end, :days).
                      merge(:course_id => id, :type => type)
          opts[:section] = meet[:section] if type == SECTION
          mid = find client, 'meetings', opts
          meets.delete mid
          inst = client.escape meet[:instructor] || ''
          query = "UPDATE meetings SET instructor = '#{inst}',
                                       deleted = 0
                                   WHERE id = #{mid}".gsub(/\n\s*/, ' ')
          @log.debug query
          client.query query
        end
      }
      update.call course[:lectures], LECTURE
      update.call course[:sections], SECTION
      if meets.size > 0
        str = meets.join ','
        query = "UPDATE meetings SET deleted = 1 WHERE id IN (#{str})"
        @log.debug query
        client.query(query)
      end

      cur += 1
      update cur, max
    end # end course
  end # end departments
  puts

  if ids.size > 0
    query = "UPDATE courses SET deleted = 1 WHERE id IN (#{ids.join ','})"
    @log.debug query
    client.query(query)
  end
end
