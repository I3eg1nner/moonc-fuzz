enum E26 { A; B }
fn f(e : E26) -> Int { match e { A => 26 } }
fn main { println(f(A)) }
