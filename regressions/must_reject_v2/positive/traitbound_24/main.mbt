trait T24 { f(Self) -> Int }
struct S24 { x24 : Int }
fn[A : T24] g(a : A) -> Int { a.f() }
fn main { println(g(S24::{x24:24})) }
