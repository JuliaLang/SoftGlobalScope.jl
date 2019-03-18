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
You can then execute the statement with `eval`. Alternatively, you can decorate
the expression with the `@softscope` macro:
```jl
julia> s = 0;

julia> @softscope for i = 1:10
           s += i
       end

julia> s
55
```
This macro should only be used in the global scope (e.g., via the REPL); using
this macro within a function is likely to lead to unintended consequences.

You can execute an entire sequence of statements using "soft" global scoping
rules via `softscope_include_string`:
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
export softscope, softscope_include_string, @softscope

if VERSION < v"0.7.0-DEV.2308" # before julia#19324 we don't need to change the ast
    softscope(m::Module, ast) = ast
    softscope_include_string(m::Module, code::AbstractString, filename::AbstractString="string") =
        @static isdefined(Base, Symbol("@__MODULE__")) ? include_string(m, code, filename) : Core.eval(m, :(include_string($code, $filename)))
else
    using Base.Meta: isexpr

    const assignments = Set((:(=), :(+=), :(-=), :(*=), :(/=), :(//=), :(\=), :(^=), :(÷=), :(%=), :(<<=), :(>>=), :(>>>=), :(|=), :(&=), :(⊻=), :($=)))
    const calls = Set((:call, :comparison, :(&&), :(||), :ref, :tuple))

    # extract the local variable names (e.g. `[:x]`) from assignments (e.g. `x=1`) etc.
    function localvars(ex::Expr)
        if isexpr(ex, :(=)) || isexpr(ex, :(::))
            return localvars(ex.args[1])
        elseif isexpr(ex, :tuple) || isexpr(ex, :block)
            return localvars(ex.args)
        else
            return Any[]
        end
    end
    localvars(ex::Symbol) = [ex]
    localvars(ex) = Any[]
    localvars(a::Vector) = vcat(localvars.(a)...)

    # Deal with assignments where the LHS is always local but the RHS might require global statements
    # For example, with previously defined a, let a = (a = 1) ; end -> let a = (global a = 1) ; end
    function localassignment(ex, globals, locals, insertglobal)
        if isexpr(ex, :block)
            args = []
            for arg in ex.args
                if isexpr(arg, :(=))
                    push!(args, Expr(arg.head, arg.args[1], _softscope(arg.args[2], globals, locals, insertglobal)))
                    union!(locals, localvars(arg.args[1]))
                elseif arg isa Symbol
                    push!(args, arg)
                else
                    error("Unknown syntax - please file an issue in the SoftGlobalScope.jl repository")
                end
            end
            return Expr(ex.head, args...)
        elseif isexpr(ex, :(=))
            return Expr(ex.head, ex.args[1], _softscope(ex.args[2], globals, locals, insertglobal))
        elseif ex isa Symbol
            return ex
        else
            error("Unknown syntax - please file an issue in the SoftGlobalScope.jl repository")
        end
    end

    """
        _softscope(ex, globals, locals, insertglobal::Bool=false)

    Transform expression `ex` to "soft" scoping rules, where `globals` is a collection
    (e.g. `Set`) of global-variable symbols to implicitly qualify with `global`, and
    `insertglobal` is whether to insert the `global` keyword at the top level of
    `ex`.  (Usually, you pass `insertglobal=false` to start with and then it is
    recursively set to `true` for local scopes introduced by `for` etcetera.)
    NOTE: `_softscope`` may mutate the `globals` argument (if there are `local` declarations.)
    """
    function _softscope(ex::Expr, globals, locals, insertglobal::Bool=false, noassignment::Bool=false)
        if isexpr(ex, :for)
            return Expr(ex.head, localassignment(ex.args[1], copy(globals), copy(locals), insertglobal),
                _softscope(ex.args[2], copy(globals), copy(locals), true))
        elseif isexpr(ex, :while)
            return Expr(ex.head, _softscope(ex.args[1], copy(globals), copy(locals), insertglobal),
                _softscope(ex.args[2], copy(globals), copy(locals), true))
        elseif isexpr(ex, :try)
            try_clause = _softscope(ex.args[1], copy(globals), copy(locals), true)
            catch_clause = _softscope(ex.args[3], copy(globals), ex.args[2] isa Symbol ? union!(locals, ex.args[2:2]) : copy(locals), true)
            if length(ex.args) == 3
                return Expr(:try, try_clause, ex.args[2], catch_clause)
            else
                finally_clause = _softscope(ex.args[4], copy(globals), copy(locals), true)
                return Expr(:try, try_clause, ex.args[2], catch_clause, finally_clause)
            end
        elseif isexpr(ex, :let)
            letlocals = union(locals, localvars(ex.args[1]))
            return Expr(ex.head, localassignment(ex.args[1], copy(globals), copy(locals), true),
                _softscope(ex.args[2], copy(globals), letlocals, true))
        elseif isexpr(ex, :block) || isexpr(ex, :if) || isexpr(ex, :elseif) || isexpr(ex, :toplevel)
            return Expr(ex.head, _softscope.(ex.args, Ref(globals), Ref(locals), insertglobal)...)
        elseif isexpr(ex, :global)
            union!(globals, localvars(ex.args))
            return ex
        elseif isexpr(ex, :local)
            union!(locals, localvars(ex.args)) # affects globals in surrounding scope!
            return ex
        elseif ex.head in calls
            return Expr(ex.head, _softscope.(ex.args, Ref(globals), Ref(locals), insertglobal, ex.head === :tuple)...)
        elseif isexpr(ex, :kw) || (noassignment && ex.head in assignments)
            return Expr(ex.head, ex.args[1], _softscope(ex.args[2], globals, locals, insertglobal))
        elseif insertglobal && ex.head in assignments
            if isexpr(ex.args[1], :call)
                return ex
            elseif ex.args[1] in globals && !(ex.args[1] in locals) # Simple assignment to global
                return Expr(:global, Expr(ex.head, ex.args[1], _softscope(ex.args[2], globals, locals, insertglobal)))
            end
            softex = Expr(ex.head, _softscope.(ex.args, Ref(globals), Ref(locals), insertglobal)...)
            if isexpr(ex.args[1], :tuple) # Assignment to a tuple
                vars = [var for var in localvars(ex.args[1].args) if (var in globals) && !(var in locals)]
                return isempty(vars) ? softex : Expr(:block, Expr(:global, vars...), softex)
            else
                return softex
            end
        elseif !insertglobal && isexpr(ex, :(=)) # only assignments in the global scope need to be considered
            union!(globals, localvars(ex))
            return ex
        else
            return ex
        end
    end
    _softscope(ex, globals, locals, insertglobal::Bool=false, noassignment::Bool=false) = ex

    softscope(m::Module, ast) = _softscope(ast, Set(@static VERSION < v"0.7.0-DEV.3526" ? names(m, true) : names(m, all=true)), Set{Symbol}())

    # we want to add line numbers to most expressions, but we can
    # only do this by wrapping them in :block (:toplevel doesn't work),
    # and some expressions are toplevel-only.  We also need to shift
    # any existing line numbers by line-1.
    const toplevel_only = (:module, :primitive, :abstract, :struct)
    _add_linenum(ex, line, filesym) = Expr(:block, LineNumberNode(line, filesym), ex)
    add_linenum(ex, line, filesym) = _add_linenum(ex, line, filesym)
    shift_linenum(ex::LineNumberNode, line, filesym) = ex.file === :none ? LineNumberNode(ex.line+line-1, filesym) : ex
    shift_linenum(ex::Expr, line, filesym) = Expr(ex.head, shift_linenum.(ex.args, line, filesym)...)
    shift_linenum(ex, line, filesym) = ex
    add_linenum(ex::LineNumberNode, line, filesym) = shift_linenum(ex, line, filesym)
    function add_linenum(ex::Expr, line, filesym)
        if ex.head == :toplevel
            return Expr(:toplevel, add_linenum.(ex.args, line, filesym)...)
        end
        exshift = shift_linenum(ex, line, filesym)
        if exshift.head in toplevel_only
            return exshift
        else
            return _add_linenum(exshift, line, filesym)
        end
    end

    function softscope_include_string(m::Module, code::AbstractString, filename::AbstractString="string")
        # read through the code line by line, keeping count to preserve line-number information
        pos = 1 # current position in the code
        lastpos = lastindex(code)
        line = 1
        retval = nothing
        filesym = Symbol(filename) # LineNumberNode needs a Symbol
        while pos ≤ lastpos
            startpos = pos
            e, pos = Meta.parse(code, startpos, greedy=true, raise=false)
            if isexpr(e, :incomplete) || isexpr(e, :error)
                throw(LoadError(filename, line,
                                ErrorException("syntax: " * e.args[1])))
            end
            if e !== nothing # ignore blank and comment lines (#12)
                e = softscope(m, add_linenum(e, line, filesym))
                retval = Core.eval(m, e)
            end
            line += count(==('\n'), SubString(code, startpos, prevind(code, pos)))
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

if VERSION < v"0.7.0-DEV.481" # the version that __module__ was introduced
    macro softscope(ast)
        esc(softscope(current_module(), ast))
    end
else
    macro softscope(ast)
        esc(softscope(__module__, ast))
    end
end

"""
    @softscope(expr)

Apply "soft" scoping rules to the argument of the macro. For example
```jl
julia> s = 0;

julia> @softscope for i = 1:10
           s += i
       end

julia> s
55
```
"""
:(@softscope)

"""
    softscope_include_string(m::Module, code::AbstractString, filename::AbstractString="string")

Like [`include_string`](@ref), but evaluates `code` using "soft"
scoping rules for the global variables defined in `m`.
"""
softscope_include_string

end # module
