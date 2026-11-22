enum E29 { A; B }
fn f(e : E29) -> Int { match e { A => 29 } }
fn main { println(f(A)) }
