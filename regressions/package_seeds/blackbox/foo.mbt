pub struct Foo {
  x : Int
}

pub fn Foo::new() -> Foo { { x: 1 } }

#deprecated("use new", skip_current_package=true)
pub fn Foo::old(self : Foo) -> Int { self.x }
