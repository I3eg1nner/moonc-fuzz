trait T3 { f(Self) -> Int }
struct S3 { x3 : Int }
impl T3 for S3 with f(self) { self.x3 }
impl T3 for S3 with f(self) { self.x3 }
fn main { println(S3::{x3:3}.f()) }
