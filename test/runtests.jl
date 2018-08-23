using SoftGlobalScope, Test

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
    @test softscope(TestMod, nl"for i=r; a += 1; end") == nl"for i=r; global a += 1; end"
    @test softscope(TestMod, nl"begin; a += 1; end") == nl"begin; a += 1; end"
    @test softscope(TestMod, nl"begin; for i=r; a += 1; end; end") == nl"begin; for i=r; global a += 1; end; end"
    @test softscope(TestMod, nl"let; a += 1; end") == nl"let; global a += 1; end"
    @test softscope(TestMod, nl"let b=2; a+=1; b=3; end") == nl"let b=2; global a+=1; b=3; end"
    @test softscope(TestMod, nl"let b::Int=2; a+=1; b=3; end") == nl"let b::Int=2; global a+=1; b=3; end"
    @test softscope(TestMod, nl"try; a=1; catch; b=2; finally; end") == nl"try; global a=1; catch; global b=2; finally; end"
    @test softscope(TestMod, nl"try; a=1; catch b; b=2; finally; end") == nl"try; global a=1; catch b; b=2; finally; end"
end

@testset "softscope_include_string" begin
    @test softscope_include_string(TestMod, "for i=1:10; a += 1; end; a") == 10
    @test softscope_include_string(TestMod, "aa=0; for i=1:10; aa += i; end; aa") == 55
end