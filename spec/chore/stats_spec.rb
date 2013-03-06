require 'spec_helper'

describe Chore::Stats do
  let(:stats) { Chore::Stats.new }
  let(:entry) { Chore::StatEntry.new(:something,nil) }

  it 'should auto create global hash when adding empty type' do
    stats.add(:completed)
    stats.get(:completed,:global).count.should == 1
  end

  it 'should group stats by type' do
    stats.add(:completed,'SimpleJob')
    5.times { stats.add(:completed,'OtherJob') }
    stats.get(:completed,'SimpleJob').count.should == 1
    stats.get(:completed,'OtherJob').count.should == 5
    stats.get(:completed,:global).count.should == 0
  end

  it 'should total stats correctly' do
    10.times { stats.add(:completed) }
    stats.get(:completed).count.should == 10
    10.times { stats.add(:completed,'SimpleJob') }
    stats.get(:completed).count.should == 20
  end

  it 'should allow a StateEntry object to be passed in' do
    stats.add(:something,entry)
    stats.get(:something).first.timestamp.should == entry.timestamp
  end

end
