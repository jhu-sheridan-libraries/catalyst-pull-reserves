# This script copies reserves information over from Horizon db to local
# db. It MUST be run under jruby (it uses the JDBC connection 
# to Sybase). Which makes things tricky to get working, sorry. Instructions below. 
#
# It does NOT use ActiveRecord, it issues direct SQL, meaning table and
# column names (both in Horizon db and local app db) are hard-coded in,
# and will need to be changed if there's a change. 
#
# It gets db connection info from config/horizon.yml and config/database.yml
# for the selected current environment. 
#
#
#  install:
#
#  Assume an rbenv install, with a jruby available, and jruby being
#  the active ruby. (For instance, run `rbenv shell jruby-1.6.7` to
#  set that as active ruby). 
#
#  We have a Gemfile here in this directory for pull reserves. 
#  run 'bundle install' from this directory, and _check in the
#  produced Gemfile.lock_ to git, so capistrano can use it
#  to install the very same version in deployment. 
#
#  This will install jdbc_mysql, which is 
#  install rvm. This is a bit trickier than it might be, you need
#     to either install it for all users, or make sure it's installed
#     for the user the script will be run as, and then install the gems
#     as that user. See https://rvm.beginrescueend.com/rvm/install
#  `rvm install jruby`
#  `rvm jruby do gem install jdbc-mysql`
# 
# jdbc-mysql gem is just a convenient gem packaging of the MySQL java JDBC
# code. 


#
# then you can:
#
# rvm jruby do ruby pull_reserves.rb [-e environment] [-c path/to/config/dir]

# Use our local Gemfile. 

require 'rubygems'
require 'bundler/setup'
require 'jdbc/jtds'
require 'jdbc/mysql'
require 'dotenv'
Dotenv.load

# get it loaded into java via jruby, don't entirely understand this
Java::net.sourceforge.jtds.jdbc.Driver

# mysql jdbc was packaged in a ruby gem for us, so we can just require like:
# but still need to get it loaded into java via jruby, don't really get it
Java::com.mysql.jdbc.Driver

require 'optparse'
require 'ostruct'
require 'yaml'
require 'erb'

options = OpenStruct.new
# defaults
options.environment = ENV['RAILS_ENV'] || "development"
options.config_path = File.expand_path("../config", __FILE__)
OptionParser.new do |opts|
  opts.on("-e", "--environment [ENVIRONMENT]", "Rails environment", "  will also take from ENV['RAILS_ENV'].","  default #{options.environment}") do |v|
    options.environment = v
  end
  opts.on("-c", "--config [PATH]", "Path to rails ./config directory", "  expecting to find horizon.yml and database.yml there.", "  default #{options.config_path}") do |v|
    options.config_path = v
  end
end.parse!


# Now fetch our horizon connection details and local db connection
# details from config yaml's

db_config_path = File.join(options.config_path, "database.yml")
local_db = YAML.load(ERB.new(File.read(db_config_path)).result)[options.environment]
raise Exception.new("Can't find database details for '#{options.environment}' in #{File.join(options.config_path, "database.yml")}" ) unless local_db.kind_of?(Hash) 

hz_config_path = File.join(options.config_path, "horizon.yml")
horizon_db = YAML.load(ERB.new(File.read(hz_config_path)).result)[options.environment]
raise Exception.new("Can't find database details for '#{options.environment}' in #{File.join(options.config_path, "horizon.yml")}" ) unless horizon_db.kind_of?(Hash)

app_jdbc_conn = java.sql.DriverManager.get_connection("jdbc:mysql://#{local_db["host"]}:#{local_db["port"]}/#{local_db["database"]}", local_db["username"], local_db["password"])
app_jdbc_stmt = app_jdbc_conn.create_statement

horizon_jdbc_conn = java.sql.DriverManager.get_connection("jdbc:jtds:sybase://#{horizon_db["host"]}:#{horizon_db["port"]}/#{horizon_db["db_name"]}", horizon_db["login"], horizon_db["password"])
horizon_jdbc_stmt = horizon_jdbc_conn.create_statement


courses_sql = <<-eos
select c.course# as course_id, c.name_reconstructed, c.location AS location_code, l.name AS location, c.comment, c.descr as course_descr, 
  cg.descr as course_group_descr
  from course c, course_group cg, location l
  where 
    c.course_group# = cg.course_group#
    and c.location = l.location
    and (select count(*) from rbr_ict ict where ict.course_group# = cg.course_group#
          -- thought that Horizon wouldn't show reserves until the reserve date happened
          -- but it looks like I was in error, ignore that, commented out: 
          -- AND (ict.reserve_date is null OR dateadd(dd, ict.reserve_date, '1/1/1970') < getdate())
          -- weirdly, rbr_status == 1 means "inactive"
          AND rbr_status != 1
          AND (ict.withdraw_date is null OR dateadd(dd, ict.withdraw_date, '1/1/1970') > getdate())
          )  > 0
  order by location, c.name_reconstructed
eos


# de/re-normalized instructor/course-id pairs. 
course_instructor_sql = <<-eos
  select distinct
     c.course#, 
     instructor = i.name_reconstructed,
     ict.location
  
  from rbr_ict ict,
        course c,
        instructor i
  where 
      c.course_group# = ict.course_group#
      AND i.instructor# = ict.instructor#
      -- thought that Horizon wouldn't show reserves until the reserve date happened
      -- but it looks like I was in error, ignore that, commented out: 
      -- AND (ict.reserve_date is null OR dateadd(dd, ict.reserve_date, '1/1/1970') < getdate())
      -- AND (ict.reserve_date is null OR dateadd(dd, ict.reserve_date, '1/1/1970') < getdate())
      -- weirdly, rbr_status == 1 means "inactive"
      AND rbr_status != 1
      AND (ict.withdraw_date is null OR dateadd(dd, ict.withdraw_date, '1/1/1970') > getdate())
  order by location
eos

# --de-normalized course-bib
course_bibs_sql = <<-eos
  select distinct
     c.course#, 
     ict.bib#
  from 
    course c,
    rbr_ict ict
  where
    c.course_group# = ict.course_group#
      -- thought that Horizon wouldn't show reserves until the reserve date happened
      -- but it looks like I was in error, ignore that, commented out: 
      --  AND (ict.reserve_date is null OR dateadd(dd, ict.reserve_date, '1/1/1970') < getdate())
      -- AND (ict.reserve_date is null OR dateadd(dd, ict.reserve_date, '1/1/1970') < getdate())
      -- weirdly, rbr_status == 1 means "inactive"
      AND rbr_status != 1
      AND (ict.withdraw_date is null OR dateadd(dd, ict.withdraw_date, '1/1/1970') > getdate())
eos





app_jdbc_conn.setAutoCommit(false) # we want all our inserts in one transaction  
  
  app_jdbc_stmt.executeUpdate("DELETE FROM reserves_course_bibs")
  
  course_bib_insert = app_jdbc_conn.prepareStatement("INSERT INTO reserves_course_bibs (reserves_course_id, bib_id) VALUES(?,?)")
  courseBibsResultSet = horizon_jdbc_stmt.execute_query(course_bibs_sql)  
  
  while (courseBibsResultSet.next ) do 
    course_bib_insert.clearParameters
    
    course_bib_insert.setObject(1, courseBibsResultSet.getObject(1))
    course_bib_insert.setObject(2, courseBibsResultSet.getObject(2))
    
    course_bib_insert.executeUpdate()
  end
  courseBibsResultSet.close
  course_bib_insert.close
  
  
  
  app_jdbc_stmt.executeUpdate("DELETE FROM reserves_course_instructors")
  
  instructor_insert = app_jdbc_conn.prepareStatement("INSERT INTO reserves_course_instructors (reserves_course_id, instructor_str) VALUES(?,?)")     
  instructorResultSet = horizon_jdbc_stmt.execute_query(course_instructor_sql)
  
  while (instructorResultSet.next ) do
    instructor_insert.clearParameters
    
    instructor_insert.setObject(1,instructorResultSet.getObject(1))
    instructor_insert.setObject(2,instructorResultSet.getObject(2))
    
    instructor_insert.executeUpdate
  end
  instructorResultSet.close
  instructor_insert.close

  
  
  
  app_jdbc_stmt.executeUpdate("DELETE FROM reserves_courses")
    
  course_insert = app_jdbc_conn.prepareStatement("INSERT INTO reserves_courses (course_id, name, location_code, location, comment, course_descr, course_group_descr) VALUES (?,?,?,?,?,?,?)")  
  coursesResultSet = horizon_jdbc_stmt.execute_query(courses_sql)
  
  while ( coursesResultSet.next ) do
    course_insert.clearParameters
    
    course_insert.setObject(1, coursesResultSet.getObject(1))
    course_insert.setObject(2, coursesResultSet.getObject(2))
    course_insert.setObject(3, coursesResultSet.getObject(3))
    course_insert.setObject(4, coursesResultSet.getObject(4))
    course_insert.setObject(5, coursesResultSet.getObject(5))
    course_insert.setObject(6, coursesResultSet.getObject(6))
    course_insert.setObject(7, coursesResultSet.getObject(7))
    
    course_insert.executeUpdate
    
  end
  coursesResultSet.close
  course_insert.close

app_jdbc_conn.commit # commit all our inserts
  
horizon_jdbc_stmt.close
horizon_jdbc_conn.close

app_jdbc_stmt.close
app_jdbc_conn.close 

if ENV['DEBUGGING']
  puts "pull reserves completed #{Time.now}"
end
