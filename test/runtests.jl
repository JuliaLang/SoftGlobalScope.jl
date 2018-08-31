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
        @test softscope(TestMod, nl"begin; aa=0; for i=1:10; aa+=i; end; end") == nl"begin; aa=0; for i=1:10; global aa+=i; end; end"
        @test softscope(TestMod, nl"begin; (aa, bb)=(0, 1); for i=1:10; aa+=i; bb+=1; end; end") == nl"begin; (aa, bb)=(0, 1); for i=1:10; global aa+=i; global bb+=1; end; end"
        @test softscope(TestMod, nl"begin; if true; aa=0; end; for i=1:10; aa+=i; end") == nl"begin; if true; aa=0; end; for i=1:10; global aa+=i; end"
        @test softscope(TestMod, nl"begin; for i=1:10; a+=1; end; if a==0; aa=2; else aa=3; end; while aa > 0; aa -= 1; end; end") == nl"begin; for i=1:10; global a+=1; end; if a==0; aa=2; else aa=3; end; while aa > 0; global aa -= 1; end; end"
        @test softscope(TestMod, nl"for i = 1:10; let a = i ; println(a) ; end ; end") == nl"for i = 1:10; let a = i ; println(a) ; end ; end"
        @test softscope(TestMod, nl"begin; local x; x = 0; for i = 1:10; x += i ; end ; end") == nl"begin; local x; x = 0; for i = 1:10; x += i ; end ; end"
        @test softscope(TestMod, nl"let x=1; x=0; for i = 1:10; x += i; end; end") == nl"let x=1; x=0; for i = 1:10; x += i; end; end"
        @test softscope(TestMod, nl"for i = 1:10; for j = 1:3; global x += 1; end; x = 3; end") == nl"for i = 1:10; for j = 1:3; global x += 1; end; x = 3; end"
    end
end

@testset "softscope_include_string" begin
    @test softscope_include_string(TestMod, "for i=1:10; a += 1; end; a") == 10
    @test softscope_include_string(TestMod, "aa=0; for i=1:10; aa += i; end; aa") == 55
end
