private module Test
  include JS::ExpandMethods

  @[JS::Method]
  def self.array(array : Array(Int32)) : String
    <<-js
      return JSON.stringify(#{array});
    js
  end

  @[JS::Method]
  def self.splat(*ints : Int32) : String
    <<-js
      return JSON.stringify(#{ints});
    js
  end

  @[JS::Method]
  def self.double_array(array : Array(Array(Int32))) : String
    <<-js
      return JSON.stringify(#{array});
    js
  end
end

it "handle primitive types" do
  Test.array([10, 20, 30]).should eq "[10,20,30]"
  Test.splat(10, 20, 30).should eq "[10,20,30]"
  Test.splat(10, 20).should eq "[10,20]"
  Test.double_array([[] of Int32, [10, 20, 30]]).should eq "[[],[10,20,30]]"
end
