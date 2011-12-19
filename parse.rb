require 'nokogiri'
require 'net/http'
require 'logger'

@log = Logger.new STDOUT
@log.level = Logger::INFO

def assert e; raise 'fail' unless e; e; end

def parse url
  @log.info "Fetching: #{url}"
  data = `curl -s #{url}`
  @log.info "Parsing: #{url}"
  # Data returned in SOC is retarded. The first course listed after the header
  # for which department it's in is missing the leading <TR> tag.
  data = data.gsub(/^<TD/, '<TR><TD')
  Nokogiri::HTML(data)
end

index = parse 'https://enr-apps.as.cmu.edu/open/SOC/web/images/documents.htm'

SPACE = "\u00a0"

def meeting course, tds, offset
  meet = {}
  meet[:days]       = tds[offset + 1].text
  meet[:begin]      = tds[offset + 2].text
  meet[:end]        = tds[offset + 3].text
  meet[:room]       = tds[offset + 4].text
  if tds[offset + 5].nil?
    assert(tds[0].text == SPACE)
    meet[:instructor] = nil
  else
    meet[:instructor] = tds[offset + 5].text
  end

  case tds[offset].text
    when 'Lec', SPACE
      @log.debug "\tAdding lecture to: #{course[:number]}"
      course[:lectures] << meet
    else
      @log.debug "\tAdding section '#{tds[offset].text}' to: #{course[:number]}"
      meet[:section] = tds[offset].text
      course[:sections] << meet
  end
end

semesters = []

index.css('a').each do |node|
  next if node['href'] !~ /sched_layout_.*htm$/

  semester = parse node['href']
  match = semester.css('p b').first.text.match(/Semester: (.*?) (\d+)/)
  season, year = assert(match[1]), assert(match[2])

  @log.info "Semester: '#{season}' Year: '#{year}'"
  table = semester.css('table').first
  
  titles = nil
  dptmt = nil
  first = false
  departments = {}
  course, cnum = nil, nil
  
  table.css('tr').each do |row|
    tds = row.css('td')
    case tds.size
      when 1
        @log.debug "Found a first row..."
        assert !first
        first = true
        next
  
      when 11
        departments[dptmt][cnum] = course if cnum
        dptmt = tds[0].text
        departments[dptmt] = {}
        @log.debug "Going to department: #{dptmt}"
  
      when 9
        case tds[0].text
          when /^\d{5}$/
            departments[dptmt][cnum] = course if cnum
            @log.debug "Parsing course: #{tds[0].text}"
            cnum = tds[0].text
            course = {}
            course[:number] = cnum
            course[:title] = tds[1].text
            course[:units] = tds[2].text
            course[:lectures] = []
            course[:sections] = []

            # Could be section, could possibly not be?
            meeting course, tds, 3

          when SPACE
            # Found another section or lecture for the previous course
            assert(course != nil && cnum != nil)
            meeting course, tds, 3

          when 'Course'
            # This is the header row for the entire sheet, we can just skip
            next
          else 
            raise "Bad first text in 9-element cell: #{tds[0].text.inspect}"
        end
  
      when 8
        assert(course != nil && cnum != nil)
        meeting course, tds, 3
  
      else
        p tds.text
        raise "Bad number of cells: #{tds.size}"
    
    end

  end

  semesters << {
    :year => year.to_i,
    :season => season,
    :departments => departments
  }
end

File.open('cache', 'wb') { |f| f << Marshal.dump(semesters) }
