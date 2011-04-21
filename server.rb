#!/usr/bin/env ruby
# 1.9


=begin

  Project Feed Farm v.0.1
  
  -- [server] --
  run ./server.rb # will show live logs of the server
  
  -- [client] --
  telnet 127.0.0.1 54321
  
  - Title: Democracy Now! 2011-04-12 Tuesday
  - Description: Headlines for April 12, 2011; Nuclear Catastrophe in Japan “Not Equal to Chernobyl,
    But Way Worse”; Human Rights Concerns Continue After Capture of Ivory Coast Strongman Laurent
    Gbagbo; "I Am Willing to Give My Life": Bahraini Human Rights Activists Risk Lives to Protest
    U.S./Saudi-Backed Repression; The Army vs. the People?: A Democracy Now! Special Report from
    Egypt
  - Date 0000-00-00
  
  -- [snip] --
  
  Connection closed by foreign host.

  * UDP and TCP support *( just TCP for now )*
  * RSS 1/2 support
=end


port = 54321
db = "FeedFarm.db"
hosting_type = "TCP" # OR UDP
update_every = 30 # minutes --- NOT YET IMPLETEMENTED ******
new_db_on_start = true # clear *** TABLE *** Every Session / Init()

# amount of stories to send at once
$minimum = 30
$maximum = 60

$feeds = %w(
  http://www.democracynow.org/democracynow.rss
  http://www.democracynow.org/podcast.xml
  http://rss.news.yahoo.com/rss/world
  http://feeds.reuters.com/reuters/worldNews?format=xml
  http://rt.com/news/today/rss/
  https://twitter.com/statuses/user_timeline/759251.rss
  https://twitter.com/statuses/user_timeline/8719302.rss
  http://www.newsonfeeds.com/section/World%20News/2/1/rss
)

# --
# --  DON'T TOUCH ANYTHING BEYOND THIS LINE
# --  IF YOU DON'T KNOW WHAT YOUR DOING
# --
require 'socket'
require 'sqlite3'
require 'open-uri'
require 'rss/1.0'
require 'rss/2.0'

if File.exists?(db)
  File.unlink(db) unless !new_db_on_start
end

rss = []
atom = []

if File.exists?(db)
  puts "Connecting to database...\n"
  $news = SQLite3::Database.open(db)
  
  puts "Connected!\n"
  
else
  puts "Creating Database...\n"
  $news = SQLite3::Database.new(db)
  
  puts "Creating Table(s)...\n"
  sql = "CREATE TABLE news (
    title VARCHAR(255) PRIMARY KEY,
    url VARCHAR(255),
    _date TIMESTAMP KEY,
    description TEXT
  )
  "
  attempts = 0
  
  begin
    attempts += 1
    $news.execute(sql)
    
  rescue Exception => ex
    if attempts != 2
      retry
    end
    
    raise "Error: #{$!}"
  end
end

def log(message)
  # date_FeedFarm_log.txt
  log = Time.now.to_s.split(' ')[0] + '_FeedFarm_log.txt'
  
  fp = File.open(log, 'a+')
  fp.write(message + "\n")
  fp.close()
  
  puts message
end

# insert story
def add(title, url, date, description)
  begin
    query = $news.prepare("INSERT INTO news (title, url, _date, description) VALUES (?, ?, ?, ?)")
    query.bind_params(title, url, date.to_s, description)
    query.execute()
  rescue Exception => ex
    puts "Error: #{$!}\n"
  end
end

# send stories over socket
def stories(socket_accept)
  stories = []
  amount = rand($maximum) + $minimum # range(min, max)
  sql = "SELECT title, description, _date, url FROM news ORDER BY _date DESC LIMIT "
  sql = sql+ amount.to_s
  
  $news.execute(sql).each do |row|
    socket_accept.puts \
      "* Title: " + row[0].to_s.strip + "\n* Description: " + row[1].to_s
    socket_accept.puts "\n* Date: " + row[2] + "\n* Source: " + row[3] + "\n\n"
  end
  
  return stories.join("\n")
end

# update database
def refreshing()
  threads = []
  
  begin
    # start a new thread for every uri download
    
    Thread.abort_on_exception = true
    t1 = Thread.new do
      
        $feeds.each do |uri|
          rss = RSS::Parser.parse(open(uri).readlines().join("\n"), false)
          
          rss.items.each do |story|
            add(story.title, story.link, story.date, story.description)
            log(Time.now.to_s.split(' ')[0] + " :  Added To DB: " + story.title)
          end
        end
        
    # t1.Thread ends
    end
    
  rescue Exception => e
    # ignore for now
  end
    
end

refreshing() # download and install stories
serv = TCPServer.new("127.0.0.1", port)

begin
  while(s = serv.accept())
    log(Time.now().to_s + " : " + s.addr.join(" ") + "\n")
    stories(s)
    s.close
  end
rescue Exception => e
  p e.to_s
ensure
  $news.close()
end