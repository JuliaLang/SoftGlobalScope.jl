using SoftGlobalScope
if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

# filter line numbers out of expressions, to make them easier to compare
nl(x) = x
nl(a::AbstractVector) = map(nl, filter(x -> !isa(x, LineNumberNode), a))
nl(ex::Expr) = Expr(ex.head, nl(ex.args)...)
macro nl_str(expr)
    :(nl(Meta.parse($expr)))
end

# test module that defines some globals
module TestMod
    a = 0
    b = 1
    c = 2
end

@testset "softscope" begin
    if VERSION < v"0.7.0-DEV.2308"
        @test softscope(TestMod, nl"for i=r; a += 1; end") == nl"for i=r; a += 1; end"
    else
        @test softscope(TestMod, nl"for i=r; a += 1; end") == nl"for i=r; global a += 1; end"
        @test softscope(TestMod, nl"while a < 3; a += 1; end") == nl"while a < 3; global a += 1; end"
        @test softscope(TestMod, nl"begin; a += 1; end") == nl"begin; a += 1; end"
        @test softscope(TestMod, nl"begin; for i=r; a += 1; end; end") == nl"begin; for i=r; global a += 1; end; end"
        @test softscope(TestMod, nl"let; a += 1; end") == nl"let; global a += 1; end"
        @test softscope(TestMod, nl"let; local a; a += 1; end") == nl"let; local a; a += 1; end"
        @test softscope(TestMod, nl"let; local a=0; a += 1; end") == nl"let; local a=0; a += 1; end"
        @test softscope(TestMod, nl"let; local a::Int=0; a += 1; end") == nl"let; local a::Int=0; a += 1; end"
        @test softscope(TestMod, nl"let; begin; local a::Int=0; end; a += 1; end") == nl"let; begin; local a::Int=0; end; a += 1; end"
        @test softscope(TestMod, nl"let b=2; a+=1; b=3; end") == nl"let b=2; global a+=1; b=3; end"
        @test softscope(TestMod, nl"let b=2, (c,d)=e; a+=1; b=3; c=4; end") == nl"let b=2, (c,d)=e; global a+=1; b=3; c=4; end"
        @test softscope(TestMod, nl"let b=2, (c′,d)=e; a+=1; b=3; c=4; end") == nl"let b=2, (c′,d)=e; global a+=1; b=3; global c=4; end"
        @test softscope(TestMod, nl"let b::Int=2; a+=1; b=3; end") == nl"let b::Int=2; global a+=1; b=3; end"
        @test softscope(TestMod, nl"try; a=1; catch; b=2; finally; end") == nl"try; global a=1; catch; global b=2; finally; end"
        @test softscope(TestMod, nl"try; a=1; catch b; b=2; finally; end") == nl"try; global a=1; catch b; b=2; finally; end"
        @test softscope(TestMod, nl"try; x=1; catch; end") == nl"try; x=1; catch; end"
        @test softscope(TestMod, nl"try; x=1; finally; end") == nl"try; x=1; finally; end"
        @test softscope(TestMod, nl"begin; aa=0; for i=1:10; aa+=i; end; end") == nl"begin; aa=0; for i=1:10; global aa+=i; end; end"
        @test softscope(TestMod, nl"begin; (aa, bb)=(0, 1); for i=1:10; aa+=i; bb+=1; end; end") == nl"begin; (aa, bb)=(0, 1); for i=1:10; global aa+=i; global bb+=1; end; end"
        @test softscope(TestMod, nl"begin; if true; aa=0; end; for i=1:10; aa+=i; end") == nl"begin; if true; aa=0; end; for i=1:10; global aa+=i; end"
        @test softscope(TestMod, nl"begin; for i=1:10; a+=1; end; if a==0; aa=2; else aa=3; end; while aa > 0; aa -= 1; end; end") == nl"begin; for i=1:10; global a+=1; end; if a==0; aa=2; else aa=3; end; while aa > 0; global aa -= 1; end; end"
        @test softscope(TestMod, nl"for i = 1:10; let a = i ; println(a) ; end ; end") == nl"for i = 1:10; let a = i ; println(a) ; end ; end"
        @test softscope(TestMod, nl"begin; local x; x = 0; for i = 1:10; x += i ; end ; end") == nl"begin; local x; x = 0; for i = 1:10; x += i ; end ; end"
        @test softscope(TestMod, nl"let x=1; x=0; for i = 1:10; x += i; end; end") == nl"let x=1; x=0; for i = 1:10; x += i; end; end"
        @test softscope(TestMod, nl"for i = 1:10; for j = 1:3; global x += 1; end; x = 3; end") == nl"for i = 1:10; for j = 1:3; global x += 1; end; x = 3; end"
        @test softscope(TestMod, nl"let; global aa = 0; for i = 1:10; aa+=i; end; end") == nl"let; global aa = 0; for i = 1:10; global aa+=i; end; end"
        @test softscope(TestMod, nl"for i = (a = 1; 1:10); end") == nl"for i = (a = 1; 1:10); end"
        @test softscope(TestMod, nl"while (a += 1) < 10 ; end") == nl"while (a += 1) < 10 ; end"
        @test softscope(TestMod, nl"let a = (a = 2); end") == nl"let a = (global a = 2); end"
        @test softscope(TestMod, nl"let a = (a = 1), b = (b = 2), c = (aa = 3); end") == nl"let a = (global a = 1), b = (global b = 2), c = (aa = 3); end"
        @test softscope(TestMod, nl"let a = (b = 1), b = (a = 2), c = (aa = 3); end") == nl"let a = (global b = 1), b = (a = 2), c = (aa = 3); end"
        @test softscope(TestMod, nl"for i = (a = 1; 1:10); for j = (a = 2; 1:10); end; end") == nl"for i = (a = 1; 1:10); for j = (global a = 2; 1:10); end; end"
        @test softscope(TestMod, nl"while (a += 1) < 10; while (b += 1) < 10; end; end") == nl"while (a += 1) < 10; while (global b += 1) < 10; end; end"
        @test softscope(TestMod, nl"let; f(a) = (a = 1); end") == nl"let; f(a) = (a = 1); end"
        @test softscope(TestMod, nl"sqrt((for i = 1:10; a+=1; end; a))") == nl"sqrt((for i = 1:10; global a+=1; end; a))"
        @test softscope(TestMod, nl"let a = (local b = 2; a = 1), b = (b = 3); end") == nl"let a = (local b = 2; global a = 1), b = (b = 3); end"
        @test softscope(TestMod, nl"f(a=(for i = 1:10; a+=1; end; a))") == nl"f(a=(for i = 1:10; global a+=1; end; a))"
        @test softscope(TestMod, nl"let a; a = 1; end") == nl"let a; a = 1; end"
        @test softscope(TestMod, nl"let a, b; a = 1; end") == nl"let a, b; a = 1; end"
        @test softscope(TestMod, nl"for i=r; true && (a += 1); end") == nl"for i=r; true && (global a += 1); end"
        @test softscope(TestMod, nl"for i=r; true || (a += 1); end") == nl"for i=r; true || (global a += 1); end"
        @test softscope(TestMod, nl"for i=r; 0 < (a += 1) < 10; end") == nl"for i=r; 0 < (global a += 1) < 10; end"
        @test softscope(TestMod, nl"for i = 1:10; x,y = (i+1, i+2); end") == nl"for i = 1:10; x,y = (i+1, i+2); end"
        @test softscope(TestMod, nl"for i = 1:10; a,x = (i+a, i+1); end") == nl"for i = 1:10; begin; global a; a,x = (i+a, i+1); end; end"
        @test softscope(TestMod, nl"for i = 1:10; a,b,x = (i+a, a+b, i+1); end") == nl"for i = 1:10; begin; global a, b; a,b,x = (i+a, a+b, i+1); end; end"
        @test softscope(TestMod, nl"j=0; for i = 1:10; (a[j+=1],x) = (i, i+1); end") == nl"j=0; for i = 1:10; (a[global j+=1],x) = (i, i+1); end"
        @test softscope(TestMod, nl"myfunc(a) = (b = 0; for i = 1:10; b += i; a += b; end; a)") == nl"myfunc(a) = (b = 0; for i = 1:10; b += i; a += b; end; a)"
        @test softscope(TestMod, nl"let; x = (a=1, aa=2); end") == nl"let; x = (a=1, aa=2); end"
        @test softscope(TestMod, nl"for i = 1:10; if true; a = 3; elseif false; a = 4; else; a = 7; end; end") == nl"for i = 1:10; if true; global a = 3; elseif false; global a = 4; else; global a = 7; end; end"
    end
end

# make == comparison of LoadErrors work in 0.6
if VERSION < v"0.7"
    Base.:(==)(a::LoadError, b::LoadError) = a.file == b.file && a.line == b.line && a.error == b.error
    Base.:(==)(a::ErrorException, b::ErrorException) = a.msg == b.msg
end

@testset "softscope_include_string" begin
    @test softscope_include_string(TestMod, "for i=1:10; a += 1; end; a") == 10
    @test softscope_include_string(TestMod, "aa=0; for i=1:10; aa += i; end; aa") == 55
    @test softscope_include_string(TestMod, "aa2=0\nfor i=1:10; aa2 += i; end\naa2") == 55
    @test softscope_include_string(TestMod, "module AModule; const amod=123; end") isa Module
    @test TestMod.AModule.amod == 123
    for (code,line) in (("1\n2\n1+",3), ("1;2;1+",1))
        try
            softscope_include_string(TestMod, code, "bar")
        catch e
            @test e == LoadError("bar", line, ErrorException("syntax: incomplete: premature end of input"))
        end
    end
    try
        softscope_include_string(TestMod, "1\n2\n1++++2", "bar")
    catch e
        @test e == LoadError("bar", 3, ErrorException("syntax: \"++\" is not a unary operator"))
    end
    softscope_include_string(TestMod, """"blah blah"\ntestdoc = 1""")
    @test TestMod.testdoc == 1
    @test Docs.docstr(Docs.Binding(TestMod, :testdoc)).text[1] == "blah blah"
    @test softscope_include_string(Main, "1\n   ") === softscope_include_string(Main, "1\n#b") === 1
end

@testset "softscope_macro" begin
    Core.eval(TestMod, :(global a = 0 ; using SoftGlobalScope))
    @test Core.eval(TestMod, :(@softscope (for i=1:10; a += 1; end; a))) == 10
    @test Core.eval(TestMod, :(@softscope (amacro=0; for i=1:10; amacro += i; end; amacro))) == 55
end
