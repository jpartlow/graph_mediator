require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

create_schema do |conn|
  conn.create_table(:people, :force => true) do |t|
    t.string :name
    t.string :type
  end

  conn.create_table(:rooms, :force => true) do |t|
    t.string :building
    t.string :number
  end

  conn.create_table(:courses, :force => true) do |t|
    t.string :name
    t.string :term
    t.integer :year
    t.belongs_to :people
    t.belongs_to :room
    t.integer :session_max
    t.integer :course_version
  end

  conn.create_table(:schedules, :force => true) do |t|
    t.belongs_to :room
    t.belongs_to :course
    t.belongs_to :session
    t.string :day_of_the_week
    t.time :start_time
    t.time :end_time
  end
  
  conn.create_table(:assistants, :force => true) do |t|
    t.belongs_to :course
    t.belongs_to :people
  end

  conn.create_table(:sessions, :force => true) do |t|
    t.belongs_to :assistant
    t.belongs_to :room
  end

  conn.create_table(:students, :force => true) do |t|
    t.belongs_to :people
    t.belongs_to :course
    t.string :grade
  end

  conn.create_table(:session_students, :force => true) do |t|
    t.belongs_to :session
    t.belongs_to :student
  end
end

class Person < ActiveRecord::Base; end
class Lecturer < Person; end
class Student < Person; end
class GraduateStudent < Student; end

class Room < ActiveRecord::Base; end

class Course < ActiveRecord::Base

  belongs_to :lecturer 
  belongs_to :room
  has_many :schedules
  has_many :assistants
  has_many :sessions, :through => :assistants
  has_many :students

#  mediate :reconciliation => :adjust_bars, :bumping => :meeting_version

end

class Schedule < ActiveRecord::Base
  belongs_to :course
  belongs_to :room  
end

class Assistant < ActiveRecord::Base
  belongs_to :course
  belongs_to :grad_student
  has_many :sessions
  has_many :schedule, :through => :session
end

class Session < ActiveRecord::Base
  belongs_to :assistant
  belongs_to :room
#  has_many :schedule, :foreign_key => 
end
