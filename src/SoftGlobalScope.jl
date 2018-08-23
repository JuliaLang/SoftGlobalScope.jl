VERSION < v"0.7.0-beta2.199" && __precompile__()

"""
SoftGlobalScope is a package that simplifies the [variable scoping rules](https://docs.julialang.org/en/stable/manual/variables-and-scoping/)
for code in *global* scope.   It is intended for interactive shells (the REPL, [IJulia](https://github.com/JuliaLang/IJulia.jl),
etcetera) to make it easier to work interactively with Julia, especially for beginners.

In particular, SoftGlobalScope provides a function `softscope` that can transform Julia code from using the default
"hard" (local) scoping rules to simpler "soft" scoping rules in global scope, and a function `softscope_include_string`
that can evaluate a whole string (similar to `include_string`) using these rules.

For example, if `s` is a global variable in the current module (e.g. `Main`), the following code is an error in
Julia 1.0:
```
for i = 1:10
    s += i     # declares a new local variable `s`
end
```
Instead, you can transform the expression using `softscope` to automatically insert the necessary `global` keyword:
```jl
julia> softscope(Main, :(for i = 1:10
           s += i
       end))
:(for i = 1:10
      #= REPL[3]:2 =#
      global s += i
  end)
```
You can then execute the statement with `eval`.  Alternatively, you can execute an entire sequence of statements
using "soft" global scoping rules via `softscope_include_string`:
```jl
julia> softscope_include_string(Main, \"\"\"
       s = 0
       for i = 1:10
           s += i
       end
       s
       \"\"\")
55
```
(This function works like `include_string`, returning the value of the last evaluated expression.)

On Julia 0.6, `softscope` is the identity and `softscope_include_string` is equivalent to
`include_string`, since the `global` keyword is not needed there.
"""
module SoftGlobalScope
export softscope, softscope_include_string

if VERSION < v"0.7.0-DEV.2308" # before julia#19324 we don't need to change the ast
    softscope(m::Module, ast) = ast
    softscope_include_string(m::Module, code::AbstractString, filename::AbstractString="string") =
        @static isdefined(Base, Symbol("@__MODULE__")) ? include_string(m, code, filename) : Core.eval(m, :(include_string($code, $filename)))
else
    using Base.Meta: isexpr

    const assignments = Set((:(=), :(+=), :(-=), :(*=), :(/=), :(//=), :(\=), :(^=), :(÷=), :(%=), :(<<=), :(>>=), :(>>>=), :(|=), :(&=), :(⊻=), :($=)))

    # extract the local variable name (e.g. `x`) from an assignment expression (e.g. `x=1`)
    localvar(ex::Expr) = isexpr(ex, :(=)) || isexpr(ex, :(::)) ? localvar(ex.args[1]) : nothing
    localvar(ex::Symbol) = ex
    localvar(ex) = nothing

    """
        _softscope(ex, globals, insertglobal::Bool=false)

    Transform expression `ex` to "soft" scoping rules, where `globals` is a collection
    (e.g. `Set`) of global-variable symbols to implicitly qualify with `global`, and
    `insertglobal` is whether to insert the `global` keyword at the top level of
    `ex`.  (Usually, you pass `insertglobal=false` to start with and then it is
    recursively set to `true` for local scopes introduced by `for` etcetera.)
    NOTE: `_softscope`` may mutate the `globals` argument (if there are `local` declarations.)
    """
    function _softscope(ex::Expr, globals, insertglobal::Bool=false)
        if isexpr(ex, :for) || isexpr(ex, :while)
            return Expr(ex.head, ex.args[1], _softscope(ex.args[2], copy(globals), true))
        elseif isexpr(ex, :try)
            try_clause = _softscope(ex.args[1], copy(globals), true)
            catch_clause = _softscope(ex.args[3], ex.args[2] isa Symbol ? setdiff(globals, ex.args[2:2]) : copy(globals), true)
            finally_clause = _softscope(ex.args[4], copy(globals), true)
            return Expr(:try, try_clause, ex.args[2], catch_clause, finally_clause)
        elseif isexpr(ex, :let)
            letglobals = setdiff(globals, isexpr(ex.args[1], :(=)) ? [localvar(ex.args[1])] : [localvar(ex) for ex in ex.args[1].args])
            return Expr(ex.head, _softscope(ex.args[1], globals, insertglobal),
                                _softscope(ex.args[2], letglobals, true))
        elseif isexpr(ex, :block) || isexpr(ex, :if)
            return Expr(ex.head, _softscope.(ex.args, Ref(globals), insertglobal)...)
        elseif isexpr(ex, :local)
            setdiff!(globals, (localvar(ex.args[1]),)) # affects globals in surrounding scope!
            return ex
        elseif insertglobal && ex.head in assignments && ex.args[1] in globals
            return Expr(:global, Expr(ex.head, ex.args[1], _softscope(ex.args[2], globals, insertglobal)))
        else
            return ex
        end
    end
    _softscope(ex, globals, insertglobal::Bool=false) = ex

    softscope(m::Module, ast) = _softscope(ast, Set(@static VERSION < v"0.7.0-DEV.3526" ? names(m, true) : names(m, all=true)))

    function softscope_include_string(m::Module, code::AbstractString, filename::AbstractString="string")
        # use the undocumented parse_input_line function so that we preserve
        # the filename and line-number information.
        expr = Base.parse_input_line("begin; "*code*"\nend\n", filename=filename)
        retval = nothing
        # expr.args should consist of LineNumberNodes followed by expressions to evaluate
        for i = 2:2:length(expr.args)
            retval = Core.eval(m, softscope(m, Expr(:block, expr.args[i-1:i]...)))
        end
        return retval
    end
end

"""
    softscope(m::Module, ast)

Transform the abstract syntax tree `ast` (a quoted Julia expression) to use "soft"
scoping rules for the global variables defined in `m`, returning the new expression.
"""
softscope

"""
    softscope_include_string(m::Module, code::AbstractString, filename::AbstractString="string")

Like [`include_string`](@ref), but evaluates `code` using "soft"
scoping rules for the global variables defined in `m`.
"""
softscope_include_string

end # module
