# SoftGlobalScope

[![Build Status](https://travis-ci.org/stevengj/SoftGlobalScope.jl.svg?branch=master)](https://travis-ci.org/stevengj/SoftGlobalScope.jl)

SoftGlobalScope is a package for the [Julia language](http://julialang.org/) that simplifies the [variable scoping rules](https://docs.julialang.org/en/stable/manual/variables-and-scoping/) for code in *global* scope.   It is intended for interactive shells (the REPL, [IJulia](https://github.com/JuliaLang/IJulia.jl), etcetera) to make it easier to work interactively with Julia, especially for beginners.

In particular, SoftGlobalScope provides a function `softscope` that can transform Julia code from using the default "hard" scoping rules to simpler "soft" scoping rules in global scope only.

## Hard and soft global scopes

[Starting in Julia 0.7](https://github.com/JuliaLang/julia/pull/19324), when you *assign to* global variables in the context of an inner scope (a `for` loop or a `let` statement) you need to explicitly declare the variable
as `global` in order to distinguish it from declaring a new variable.  We refer to this as "hard" scoping rules.  For example, the following code gives an warning in 0.7:

```jl
julia> s = 0
0

julia> for i = 1:10
           s = s + i
       end
┌ Warning: Deprecated syntax `implicit assignment to global variable `s``.
└ Use `global s` instead.
```

and an error in Julia 1.0:

```jl
julia> s = 0
0

julia> for i = 1:10
           s = s + i   # wrong: defines a new local variable s
       end
ERROR: UndefVarError: s not defined
```

To make it work in 1.0, you need a `global` declaration:
```jl
julia> for i = 1:10
           global s = s + i
       end

julia> s      # should be 1 + 2 + ⋯ + 10 = 55
55
```

This only applies to *global* variables; similar code *inside a function* (or whenever `s` is a *local* variable) works fine without any added keyword:
```jl
julia> function f(n)
           s = 0
           for i = 1:n
               s = s + i
           end
           return s
       end
f (generic function with 1 method)

julia> f(10)
55
```

There were [various reasons](https://github.com/JuliaLang/julia/pull/19324) for this scoping rule, e.g. to facilitate [static analysis](https://en.wikipedia.org/wiki/Static_program_analysis) by the compiler, and it isn't too onerous in "serious" Julia code where [little code executes in global scope](https://docs.julialang.org/en/stable/manual/performance-tips/#Avoid-global-variables-1).

However, for *interactive* use, especially for new users, the necessity of the `global` keyword, and the difference between code in local and global scopes, [can be confusing](https://github.com/JuliaLang/julia/issues/28789).   The SoftGlobalScope package exists to make it easier for *interactive shells* to automatically insert the `global` keyword in common cases, what we term "soft" global scope.

## Usage

The `SoftGlobalScope` module exports two functions `softscope` and `softscope_include_string`, and a macro `@softscope`:

You can transform the expression using `softscope(module, expression)` to automatically insert the necessary `global` keyword.  For example, assuming that the module `Main` has a global variable `s` (as above), you can do:
```jl
julia> softscope(Main, :(for i = 1:10
           s += i
       end))
:(for i = 1:10
      #= REPL[3]:2 =#
      global s += i
  end)
```
You can then execute the statement with `eval`. Alternatively, you can decorate the expression with the `@softscope` macro:
```jl
julia> s = 0;

julia> @softscope for i = 1:10
           s += i
       end

julia> s
55
```
This macro should only be used in the global scope (e.g., via the REPL); using this macro within a function is likely to lead to unintended consequences.

You can execute an entire sequence of statements using "soft" global scoping rules via `softscope_include_string(module, string, filename="string")`:
```jl
julia> softscope_include_string(Main, """
       s = 0
       for i = 1:10
           s += i
       end
       s
       """)
55
```
(This function works like `include_string`, returning the value of the last evaluated expression.)

In Julia 0.6, no code transformations are required, so `softscope` returns the original expression
and `softscope_include_string` is equivalent to `include_string`.

## Contact

SoftGlobalScope was written by [Steven G. Johnson](http://math.mit.edu/~stevenj/) and is free/open-source software under the [MIT/Expat license](LICENSE.md).  Please file bug reports and feature requests at the [SoftGlobalScope github page](https://github.com/stevengj/SoftGlobalScope.jl).
