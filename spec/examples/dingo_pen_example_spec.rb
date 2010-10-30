require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require 'aasm'

# Okay I lied.  This example has dingos.

create_schema do |conn|
  
  conn.create_table(:dingo_pens, :force => true) do |t|
    t.integer :pen_number
    t.integer :dingos_count
    t.integer :feed_rate
    t.integer :biscuit_minimum
    t.integer :biscuit_maximum
    t.float :total_biscuits
    t.float :total_biscuit_weight
    t.integer :lock_version, :default => 0
    t.timestamps
  end
 
  conn.create_table(:dingos, :force => true) do |t|
    t.belongs_to :dingo_pen
    t.string :name
    t.string :breed
    t.integer :voracity
    t.integer :aasm_state
    t.integer :lock_version, :default => 0
    t.timestamps
  end

  conn.create_table(:biscuits, :force => true) do |t|
    t.belongs_to :dingo_pen
    t.string :type
    t.float :weight
    t.integer :amount
    t.integer :lock_version, :default => 0
    t.timestamps
  end

end

# A dingo.
class Dingo < ActiveRecord::Base
  belongs_to :dingo_pen, :counter_cache => true
  include AASM
  aasm_initial_state :hungry
  aasm_state :hungry
  aasm_state :satiated
  aasm_event :eat do
    transitions :from => :hungry, :to => :satiated
  end
  aasm_event :run do
    transitions :from => :satiated, :to => :hungry
  end
end

# A bunch of biscuits.
class Biscuit < ActiveRecord::Base
  belongs_to :dingo_pen
end

class BigBiscuit < Biscuit; end
class LittleBiscuit < Biscuit; end

class DingoPen < ActiveRecord::Base
  has_many :dingos
  has_many :biscuits

  include GraphMediator

  def purchase_biscuits
    puts :purchase_biscuits
  end

  mediate :purchase_biscuits,
    :dependencies => [Dingo, Biscuit],
    :when_reconciling => [:adjust_biscuit_supply, :feed_dingos],
    :when_cacheing => :calculate_biscuit_totals
  
  def adjust_biscuit_supply
    biscuits.each do |b|
      b.amount = DingoPen.shovel_biscuits((biscuit_minimum + biscuit_maximum)/2) if b.amount < biscuit_minimum 
    end
  end

  def feed_dingos
    dingos.each { |d| d.eat if d.hungry? }
  end

  def calculate_biscuit_totals
    update_attributes(
      :total_biscuits => biscuits.sum('amount'),
      :total_biscuit_weight => biscuits.sum('weight * amount')
    )
  end

  # Class methods
  class << self
    # simulates the shoveling of biscuits into DingoPen feeders from the
    # theoretically BiscuitStore
    def shovel_biscuits(amount)
      return amount
    end
  end
end

describe "DingoPen" do

  before(:each) do
    @dingo_pen_attributes = {
      :pen_number => 42,
      :feed_rate => 10,
      :biscuit_minimum => 50,
      :biscuit_maximum => 100,
    }
  end

  it "should initialize" do
    dp = DingoPen.new
  end

  it "should create" do
    dp = DingoPen.create!(@dingo_pen_attributes)
    dp.lock_version.should == 1
  end

  it "should create with dingos and biscuits" do
    dp = DingoPen.new(@dingo_pen_attributes)
    dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
    dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
    dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
    dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
    dp.save!
    dp.lock_version.should == 1
  end

  # Shouldn't fail on new, because no one else has should have a handle on the instance yet.
  context "locking scenarios on create" do

    it "should succeed" do
      # because the rows do not exist until the mediation transaction completes
      # so no one else is in a position to write first
      dp = DingoPen.new(@dingo_pen_attributes)
      dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
      dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
      dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
      dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
      dp.save!
    end

    it "has the potential for overwriting if mediation off" do
      begin
        DingoPen.disable_all_mediation!
        dp = DingoPen.new(@dingo_pen_attributes)
        dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
        dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
        dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
        dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
        dp.save!
        dp.reload
        dp.calculate_biscuit_totals
        !dp.lock_version.should == 1
raise('finish me')
        pp dp
        dp.reload
        pp dp
      ensure
        DingoPen.enable_all_mediation!
      end
    end

  end

  context "locking scenarios on update" do
    it "should test update"
  end

  context "locking scenarios on delete" do
    it "should test delete"
  end
end
