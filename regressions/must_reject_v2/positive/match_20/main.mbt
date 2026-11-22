enum E20 { A; B }
fn f(e : E20) -> Int { match e { A => 20 } }
fn main { println(f(A)) }
