trait T29 { f(Self) -> Int }
struct S29 { x29 : Int }
fn[A : T29] g(a : A) -> Int { a.f() }
fn main { println(g(S29::{x29:29})) }
