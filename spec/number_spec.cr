require "web"

private module Test
  include JavaScript::ExpandMethods

  @[JavaScript::Method]
  def self.add(first : Int32, second : Int32) : Int32
    <<-js
      return #{first} + #{second};
    js
  end
end

it "handle primitive types" do
  Test.add(2, 3).should eq 5
end
