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

it "handle primitive types" do
  Test.len("Hello!").should eq 6
end
