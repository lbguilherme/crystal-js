private module Test
  include JavaScript::ExpandMethods

  @[JavaScript::Method]
  def self.add32(first : Int32, second : Int32) : Int32
    <<-js
      if (typeof #{first} !== "number" || typeof #{second} !== "number") {
        throw new Error();
      }
      return #{first} + #{second};
    js
  end

  @[JavaScript::Method]
  def self.and(first : Bool, second : Bool) : Bool
    <<-js
      if (typeof #{first} !== "boolean" || typeof #{second} !== "boolean") {
        throw new Error();
      }
      return #{first} && #{second};
    js
  end
end

it "handle primitive types" do
  Test.add32(2, 3).should eq 5
  Test.and(true, true).should be_true
  Test.and(true, false).should be_false
end
