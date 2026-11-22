struct A { x: @utils.List[B] }
pub(all) struct B {  }

impl Show for A with to_string(self) { self.x.join(" ") }
impl Show for A with output(self, logger) { logger.write_string(self.to_string()) }
impl Show for B with to_string(_self) { "" }
impl Show for B with output(_self, _logger) { }

fn main {
  let x = @utils.List::new();
  x.push_back(A :: { x: @utils.List::new() })
  println(x)
}
