require "web"

private module Test
  include JavaScript::ExpandMethods

  @[JavaScript::Method]
  def self.len(str : String) : Int32
    <<-js
      return #{str}.length;
    js
  end
end

describe "string" do
  it "handle primitive types" do
    Test.len("Hello!").should eq 6
  end

  it "has a working wrapper" do
    str = JavaScript::String.new("Hello!")
    str.length.should eq 6

    JavaScript::String.new("☃★♲").code_point_at(1).should eq 9733
    JavaScript::String.new("☃★♲").at(1).should eq "★"
    str.ends_with("llo!").should be_true
    str.ends_with("what").should be_false
  end
end
