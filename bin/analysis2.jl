#!/usr/bin/env julia

using PicoSAT

const packages = sort!(collect(keys(pkgs)), by=lowercase)
const versions = [(p, v) for p in packages for v in sort!(collect(keys(pkgs[p].versions)))]
const requirements = [filter!(x -> x != "julia",
        sort!(collect(keys(pkgs[p].versions[v].requires)), by=lowercase))
    for (p, v) in versions]

const subpackages =
    unique([versions[i][1] => requirements[i] for (i, v) in enumerate(versions)])

R = I + sparse(
    [i for (i, (p1, r1)) in enumerate(subpackages),
           (j, (p2, r2)) in enumerate(subpackages) if p1 ∈ r2],
    [j for (i, (p1, r1)) in enumerate(subpackages),
           (j, (p2, r2)) in enumerate(subpackages) if p1 ∈ r2], 1)

for _ = 1:typemax(Int)
    n = countnz(R)
    R = dropzeros!(min.(1, R^2))
    n == countnz(R) && break
end

function build_cnf(R, a)
    # all dependencies
    v = find(R[:, a])
    # require `a` itself
    cnf = [[findfirst(v, a)]]
    # requirements of subpackages
    for (i, b) in enumerate(v)
        B = subpackages[b]
        n = length(cnf)
        for _ in B[2]
            push!(cnf, [-i])
        end
        for (j, c) in enumerate(v)
            C = subpackages[c]
            k = findfirst(B[2], C[1])
            k != 0 && push!(cnf[n+k], j)
        end
    end
    # subpackages of the same package are mutually exclusive
    for (i, b) in enumerate(v),
        (j, c) in enumerate(v)
        i == j && continue
        B, C = subpackages[b], subpackages[c]
        B[1] == C[1] && push!(cnf, [-i, -j])
    end
    return cnf
end
