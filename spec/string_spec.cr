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

    emojis = JS::String.new("☃★♲")
    emojis.code_point_at(1).should eq 9733
    emojis.at(1).should eq JS::String.new("★")
    emojis.at(1).to_crystal.should eq "★"
    str.ends_with("llo!").should be_true
    str.ends_with("what").should be_false
    JS::String.from_code_point(9731, 9733, 9842).should eq emojis
  end
end
