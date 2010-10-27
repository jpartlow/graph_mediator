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
    t.integer :dingo_pen_version
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
    :when_cacheing => :calculate_biscuit_totals,
    :bumps => :dingo_pen_version
  
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
    dp.dingo_pen_version.should == 1
  end

  it "should create with dingos and biscuits" do
    dp = DingoPen.new(@dingo_pen_attributes)
    dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
    dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
    dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
    dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
    dp.save!
    dp.dingo_pen_version.should == 1
    pp dp
  end
end
