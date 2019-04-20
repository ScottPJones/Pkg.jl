#!/usr/bin/env julia

import Pkg
import Pkg.Types: VersionSpec, VersionRange, VersionBound, semver_spec
import Base: thismajor, thisminor, thispatch, nextmajor, nextminor, nextpatch

const STDLIBS = [
    "Base64"
    "CRC32c"
    "Dates"
    "DelimitedFiles"
    "Distributed"
    "FileWatching"
    "Future"
    "InteractiveUtils"
    "Libdl"
    "LibGit2"
    "LinearAlgebra"
    "Logging"
    "Markdown"
    "Mmap"
    "Pkg"
    "Printf"
    "Profile"
    "Random"
    "REPL"
    "Serialization"
    "SHA"
    "SharedArrays"
    "Sockets"
    "SparseArrays"
    "Statistics"
    "SuiteSparse"
    "Test"
    "Unicode"
    "UUIDs"
]

function uuid(name::AbstractString)
    if name == "Pkg"
        return "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
    elseif name == "Statistics"
        return "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
    else
        string(Pkg.METADATA_compatible_uuid(String(name)))
    end
end

function uses(repo::AbstractString, lib::AbstractString)
    pattern = string(raw"\b(import|using)\s+((\w|\.)+\s*,\s*)*", lib, raw"\b")
    success(`git -C $repo grep -Eq $pattern -- '*.jl'`)
end

function semver(intervals)
    spec = String[]
    for ival in intervals
        if ival.upper == v"∞"
            push!(spec, "≥ $(thispatch(ival.lower))")
        else
            lo, hi = ival.lower, ival.upper
            if lo.major < hi.major
                push!(spec, "^$(lo.major).$(lo.minor).$(lo.patch)")
                for major = lo.major+1:hi.major-1
                    push!(spec, "~$major")
                end
                for minor = 0:hi.minor-1
                    push!(spec, "~$(hi.major).$minor")
                end
                for patch = 0:hi.patch-1
                    push!(spec, "=$(hi.major).$(hi.minor).$patch")
                end
            elseif lo.minor < hi.minor
                push!(spec, "~$(lo.major).$(lo.minor).$(lo.patch)")
                for minor = lo.minor+1:hi.minor-1
                    push!(spec, "~$(hi.major).$minor")
                end
                for patch = 0:hi.patch-1
                    push!(spec, "=$(hi.major).$(hi.minor).$patch")
                end
            else
                for patch = lo.patch:hi.patch-1
                    push!(spec, "=$(hi.major).$(hi.minor).$patch")
                end
            end
        end
    end
    return join(spec, ", ")
end

if !isempty(ARGS) && ARGS[1] == "-f"
    const force = true
    popfirst!(ARGS)
else
    const force = false
end
isempty(ARGS) && (push!(ARGS, pwd()))

function check_empty(p::Pkg.Types.Project)
    for f in fieldnames(Pkg.Types.Project)
        val = getfield(p, f)
        val === nothing || isempty(val) || return false
    end
    true
end

for arg in ARGS
    dir = abspath(expanduser(arg))
    if !isdir(dir)
        @error "$arg does not appear to be a package (not a directory)"
        continue
    end

    name = basename(dir)
    if isempty(name)
        dir = dirname(dir)
        if !isdir(dir)
            @error "$arg does not appear to be a package (not a directory)"
            continue
        end
        name = basename(dir)
    end
    endswith(name, ".jl") && (name = chop(name, tail=3))

    require_file = joinpath(dir, "REQUIRE")
    if !isfile(require_file)
        @error "$arg does not appear to be a package (no REQUIRE file)"
        continue
    end

    project = Dict(
        "name" => name,
        "uuid" => uuid(name),
        "deps" => Dict{String,String}(),
        "compat" => Dict{String,String}(),
        "extras" => Dict{String,String}(),
    )

    test_require_file = joinpath(dir, "test", "REQUIRE")

    for (file, section) in ((require_file, "deps"),
                            (test_require_file, "extras"))
        isfile(file) || continue
        reqs = Pkg.Pkg2.Reqs.read(file)
        for req in reqs
            req isa Pkg.Pkg2.Reqs.Requirement || continue
            dep = String(req.package)
            if dep != "julia"
                project[section][dep] = uuid(dep)
            end
            if req.versions != Pkg.Pkg2.Pkg2Types.VersionSet()
                project["compat"][dep] = semver(req.versions.intervals)
            end
        end

        for stdlib in STDLIBS
            if uses(dirname(file), stdlib)
                project[section][stdlib] = uuid(stdlib)
            end
        end
    end

    if !isempty(project["extras"])
        project["targets"] = Dict("test" => collect(keys(project["extras"])))
        haskey(project["deps"], "Test") && delete!(project["deps"], "Test")
    end

    project_file = joinpath(dir, "Project.toml")
    oldproject = Pkg.Types.read_project(project_file)
    if check_empty(oldproject)
        println(stderr, "Generating project file for $name: $project_file")
        Pkg.Types.write_project(Pkg.Types.Project(project), project_file)
    elseif force
        println(stderr, "Overwriting project file for $name: $project_file")
        Pkg.Types.write_project(Pkg.Types.Project(project), project_file)
    elseif isempty(oldproject.compat)
        if isempty(project["compat"])
            println(stderr, "No changes needed to $name: $project_file")
            continue
        end
        println(stderr, "Adding compat section to $name: $project_file")
        open(project_file, "a") do io
            println(io)
            Pkg.TOML.print(io, Dict("compat" => project["compat"]))
        end
    else
        @error "$name: $project_file already has a [compat] section"
    end
end
