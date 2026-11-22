trait T3 { f(Self) -> Int }
struct S3 { x3 : Int }
fn[A : T3] g(a : A) -> Int { a.f() }
fn main { println(g(S3::{x3:3})) }
