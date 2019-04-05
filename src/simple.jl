using PyPlot
using LinearAlgebra
using PyTensorFlow
using PyCall
np = pyimport("numpy")
include("poisson_op.jl")

# Solver parameters
m = 20
n = 20
h = 0.01
T = 1
NT = 100
Δt = T/NT 
x = (1:m)*h|>collect
z = (1:n)*h|>collect
X, Z = np.meshgrid(x, z)


# todo 
#=
Krw, Kro -- function mxn tensor to mxn tensor
μw, μo -- known mxn
ρw, ρo -- known mxn
K -- scalar
g -- constant ≈ 9.8?
ϕ -- known mxn
=#

function Base.:get(o::Union{Array,PyObject}, i::Int64, j::Int64)
    if i==-1
        ii = 1:m-2
    elseif i==0
        ii = 2:m-1
    else
        ii = 3:m
    end
    if j==-1
        jj = 1:n-2
    elseif j==0
        jj = 2:n-1
    else
        jj = 3:n
    end
    return o[ii,jj]
end

function G(f, p)
    f1 = (get(f, 0, 0) + get(f, 1, 0))/2
    f2 = (get(f, -1, 0)+get(f, 0, 0))/2
    f3 = (get(f,0,1) + get(f,0,0))/2
    f4 = (get(f,0,-1)+get(f,0,0))/2
    rhs = -f1*(get(p,1,0)-get(p,0,0)) +
            f2*(get(p,0,0)-get(p,-1,0)) -
            f3*(get(p,0,1)-get(p,0,0)) +
            f4*(get(p,0,0)-get(p,0,-1))
    p = scatter_add(p, 2:m-1, 2:n-1, rhs/h^2)
end


# variables : sw, u, v, p
# (time dependent) parameters: qw, qo, ϕ
function onestep(sw, p, qw, qo)
    # step 1: update p
    λw = Krw(sw)/μw
    λo = Kro(1-sw)/μo
    λ = λw + λo
    f = λw/λ
    q = qw + qo
    Pc = zeros(m, n)
    Θ = G((λw*ρw+λo*ρo)*g, Z)
    p = poisson_op(λ*K, Θ+q, h)


    # step 2: update u, v
    rhs_u = -K*get(λ, 0, 0)/h*(get(p, 1, 0) - get(p, 0, 0))
    rhs_v = -K*get(λ, 0, 0)/h*(get(p, 0, 1) - get(p, 0, 0)) +
            K*get(λw*ρw+λo*ρo, 0, 0)*g
    u = constant(zeros(m, n))
    v = constant(zeros(m, n))
    u = scatter_add(u, 2:m-1, 2:n-1, rhs_u)
    v = scatter_add(v, 2:m-1, 2:n-1, rhs_v)

    # step 3: update sw
    rhs = get(qw, 0, 0) - (get(f, 1, 0)-get(f, 0, 0))/h*get(u, 0, 0) -
            (get(f, 0, 1)-get(f, 0, 0))/h*get(v, 0, 0) -
            get(f, 0, 0) * (get(u, 0, 0)-get(u, -1, 0)/h + (get(v, 0, 0)-get(v, 0, -1))/h) -
            G(K*f*λo*(ρw-ρo)*g, Z) 
    rhs = Δt*rhs/get(ϕ, 0, 0) + get(sw, 0, 0)
    sw = scatter_add(sw, 2:m-1, 2:n-1, rhs)
    return sw, p
end



"""
solve(qw, qo, sw0, p0)

Solve the two phase flow equation. 
`qw` and `qo` -- `NT x m x n` numerical array, `qw[i,:,:]` the corresponding value of qw at i*Δt
`sw0` and `p0` -- initial value for `sw` and `p`. `m x n` numerical array.
"""
function solve(qw, qo, sw0, p0)
    qw_arr = constant(qw) # qw: NT x m x n array
    qo_arr = constant(qo)
    function condition(i, tas...)
        i <= NT
    end
    function body(i, tas...)
        ta_sw, ta_p = tas
        sw, p = onestep(read(ta_sw, i), read(ta_p, i), qw_arr[i], qo_arr[i])
        ta_sw = write(ta_sw, i+1, sw)
        ta_p = write(ta_p, i+1, p)
        i+1, ta_sw, ta_p
    end
    ta_sw, ta_p = TensorArray(NT), TensorArray(NT)
    ta_sw = write(ta_sw, 1, constant(sw0))
    ta_p = write(ta_p, 1, constant(p0))
    i = constant(1, dtype=Int32)
    _, ta_sw, ta_p = while_loop(condition, body, [i, ta_sw, ta_p])
    out_sw, out_p = stack(ta_sw), stack(ta_p)
end

function vis(val, args...;kwargs...)
    close("all")
    ns = Int64.(round.(LinRange(1,NT,9)))
    for i = 1:ns
        subplot(330+i)
        imshow(val[i,:,:], args...;kwargs...)
    end
end

# Step 1: Assign numerical values to qw, qo, sw0, p0
# qw = 
# qo = 
# sw0 = 
# p0 = 

# Step 2: Construct Graph
out_sw, out_p = solve(qw, qo, sw0, p0)

# Step 3: Run
sess = Session()
init(sess)
sw, p = run(sess, [out_sw, out_p])

# Step 4: Visualize
vis(sw)