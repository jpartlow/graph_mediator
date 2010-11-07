require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

create_schema do |conn|
  conn.create_table(:changes_roots, :force => true) do |t|
    t.string :name
    t.string :state
    t.integer :changes_dependents_count
  end
  conn.create_table(:changes_dependents, :force => true) do |t|
    t.string :name
    t.integer :number
    t.belongs_to :changes_root
  end
end

class ChangesDependent < ActiveRecord::Base
  belongs_to :changes_root, :counter_cache => true
end
class ChangesRoot < ActiveRecord::Base
  cattr_accessor :tests
  has_many :changes_dependents
  include GraphMediator
  mediate :dependencies => [ChangesDependent]
  mediate_reconciles :reconciles do |instance| 
    instance.tests.call(instance) unless instance.tests.nil?
  end
  def reconciles; :reconciles; end
end

describe "GraphMediator change tracking scenarios" do

  before(:each) do
    ChangesRoot.tests = nil
    @today = Date.today
  end

  it "should track changes to mediated instance" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    r.state = :one
    changes = r.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.changes.should == {}
      instance.mediated_changes.should == { ChangesRoot => { r.id => changes } }
      run = true
    end
    r.save!
    run.should be_true 
  end

  it "should track changes to a newly created mediated instance" do
    r = ChangesRoot.new(:name => :foo)
    changes = r.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.should equal(r)
      instance.changes.should == {}
      instance.mediated_changes.should == { ChangesRoot => { :_created => [changes] } }
      run = true
    end
    r.save!
    run.should be_true
  end

  it "should track addition of a dependent" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    d = r.changes_dependents.build(:name => :bar)
    changes = d.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.mediated_changes.should == { ChangesDependent => { :_created => [ changes ] } }
      run = true
    end
    d.save!
    run.should be_true
  end

  it "should track changes to a dependent" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    d = r.changes_dependents.create!(:name => :bar)
    d.number = 2
    changes = d.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.mediated_changes.should == { ChangesDependent => { d.id => changes } }
      run = true
    end
    d.save!
    run.should be_true
  end

  it "should track deletion of a dependent" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    d = r.changes_dependents.create!(:name => :bar)
    run = false
    r.tests = Proc.new do |instance|
      instance.mediated_changes.should == { ChangesDependent => { :_destroyed => [d.id] } }
      run = true
    end
    d.destroy
    run.should be_true
  end

end
