trait T10 { f(Self) -> Int }
struct S10 { x10 : Int }
impl T10 for S10 with f(self) { self.x10 }
impl T10 for S10 with f(self) { self.x10 }
fn main { println(S10::{x10:10}.f()) }
