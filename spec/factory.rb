require 'factory_girl'

@today = Date.today

Factory.sequence :name do |n|
  "John Doe#{n}"
end

Factory.define :reservation do |i|
  i.name Factory.next(:name)
  i.starts @today
  i.ends @today
end
