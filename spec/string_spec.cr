private module Test
  include JS::ExpandMethods

  @[JS::Method]
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
    str = JS::String.new("Hello!")
    str.length.should eq 6

    JS::String.new("☃★♲").code_point_at(1).should eq 9733
    JS::String.new("☃★♲").at(1).should eq JS::String.new("★")
    JS::String.new("☃★♲").at(1).to_crystal.should eq "★"
    str.ends_with("llo!").should be_true
    str.ends_with("what").should be_false
  end
end
