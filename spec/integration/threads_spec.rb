require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

describe "mediated_transactions in different threads" do

  before(:all) do
    ActiveRecord::Base.establish_connection({'adapter' => 'sqlite3', 'database' => 'thread-test'})
  end

  after(:all) do
    ActiveRecord::Base.establish_connection({'adapter' => 'sqlite3', 'database' => ':memory:'})
  end

  before(:each) do
    load_traceable_callback_tester
    @t = Traceable.new(:name => :gizmo)
    @t.save_without_mediation! 
  end

  after(:each) do
    Object.__send__(:remove_const, :Traceable)
  end

  # This will produce two warnings regarding overlapping transactions
  it "should be different instances" do
    objectid1, objectid2 = nil, nil
    mediator1, mediator2 = nil, nil

#    puts 'start thread 1'
    thread1 = Thread.new do
      t1 = Traceable.find(@t.id)
#      puts 'preparing to mediate transaction on thread 1'
      mediator1 = t1.__send__(:_get_mediator)
#      puts 'mediating transaction on thread 1'
      Kernel.sleep(2)
#      puts 'thread 1 finished'
    end

#    puts 'sleeping kernel 1'
    Kernel.sleep(1)

#    puts 'start thread 2'
    thread2 = Thread.new do
        t2 = Traceable.find(@t.id)
#        puts 'preparing to mediate transaction on thread 2'
        mediator2 = t2.__send__(:_get_mediator)
#        puts 'mediating transaction on thread 2'
        Kernel.sleep(1)
#        puts 'thread 2 finished'
    end

#    puts 'finishing thread 1'
    thread1.join
#    puts 'finishing thread 2'
    thread2.join
#    pp mediator1, mediator2
    mediator1.should_not equal(mediator2)
  end

end
