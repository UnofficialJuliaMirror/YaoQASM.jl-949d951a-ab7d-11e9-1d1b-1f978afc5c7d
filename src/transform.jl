using MLStyle.Record
using Yao
@as_record Struct_pi
@as_record Struct_fnexp
@as_record Struct_atom
@as_record Struct_mainprogram
@as_record Struct_ifstmt
@as_record Struct_neg
@as_record Token

abstract type AbsCtx{From, To} end
struct Ctx1 <: AbsCtx{:qasm, :qbir}
    qregs :: Vector{Tuple{Symbol, Int}}
end

function index_q(ctx1::Ctx1, reg::Symbol)
    i = 1
    span = 0
    for (k, n) in ctx1.qregs
        span = n
        if k == reg
            break
        end
        i += span
    end
    return Int[i + e for e in 1:span]
end

function index_q(ctx1::Ctx1, reg::Symbol, ind::Int)
    Int[index_q(ctx1, reg)[ind]]
end


trans(qasm, ctx) =
    function app(op, args...)
        args = map(rec, args)
        op = Symbol(op)
        :($op($(args...)))
    end

    rec(qasm) = trans(qasm, ctx)
    @match qasm begin
        Struct_pi(_) => Base.pi
        Token{:real}(str) => parse(Float64, str)
        Token{:nninteger}(str) => parse(Int64, str)
        Struct_atom(atom) => rec(atom)
        Struct_neg(value) => :(-$(rec(value)))
        Struct_exp(l, op=Token(str=op), r) => app(op, l, r)
        Struct_exp(l, op=Token(str=op), r) => app(op, l, r)
        Struct_fnexp(fn = Token(str=fn), arg) =>
            let fn = @match fn begin
                        "sin" => sin
                        "cos" => cos
                        _     => error("not impl yet")
                    end
                app(fn, arg)
            end
        Struct_explist(hd, tl=nothing) => [rec(hd)]
        Struct_explist(hd, tl) => [rec(hd), rec(tl)...]
        Struct_argument(id=Token(str=id), arg=nothing) =>
            index_q(ctx1, Symbol(id))
        Struct_argument(id=Token(str=id), arg=Token(str=int)) =>
            index_q(ctx1, Symbol(id), parse(Int, int))

        Struct_idlist(hd=Token(str=hd), tl=noting) => [Symbol(hd)]
        Struct_idlist(hd=Token(str=hd), tl) => [Symbol(hd), rec(tl)...]
        Struct_cx(out1, out2) =>
            let ref1 = rec(out1),
                ref2 = rec(out2)
                :(CX($ref1, $ref2))
            end
        Struct_u(in1, in2, in3, out) =>
            let (a, b, c) = map(rec, (in1, in2, in3)),
                ref = rec(out)
                :(U($a, $b, $c, $ref))
            end
        Struct_iduop(gate_name = Token(str=gate_name), nothing, out) =>
            let ref = rec(out),
                gate_name = Symbol(gate_name)
                :($gate_name($ref))
            end
        Struct_gate(
            decl = Struct_gatedecl(id=Token(str=fid), args=nothing, outs),
            goplist = (nothing && Do(goplist=[])) || (goplist && goplist = map(rec, goplist))
         ) =>
            let out_ids :: Vector{Symbol} = trans(outs)
                quote
                    function $fid($(out_ids...))
                        $(goplist...)
                    end
                end
            end
    end