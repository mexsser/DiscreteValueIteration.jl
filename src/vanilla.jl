type ValueIterationSolver <: Solver
    # Functions required:
    # n_states, n_actions
    # states, actions!
    # create_action, create_transtion, create_interpolants
    # transition!, intrpolants!
    # weight, index
    max_iterations::Int64
    tolerance::Float64
end
function ValueIterationSolver(;max_iterations::Int64=100, tolerance::Float64=1e-3)
    return ValueIterationSolver(max_iterations, tolerance)
end

type ValueIterationPolicy <: Policy
    qmat::Matrix{Float64}
    util::Vector{Float64}
    policy::Vector{Int64}
    action_map::Vector{Action}
    include_Q::Bool
    # constructor with an option to pass in generated alpha vectors
    function ValueIterationPolicy(pomdp::POMDP; 
                                  utility::Vector{Float64}=Array(Float64,0),
                                  include_Q::Bool=false)
        ns = n_states(pomdp)
        na = n_actions(pomdp)
        self = new()
        if !isempty(utility)
            @assert size(utilty) == ns "Input utility dimension mismatch"
            self.util = utility
        else
            self.util = zeros(ns)
        end
        am = Action[]
        space = actions(pomdp)
        for a in domain(space)
            push!(am, a)
        end
        self.action_map = am
        self.policy = zeros(Int64,ns)
        include_Q ? self.qmat = zeros(ns,na) : self.qmat = zeros(0,0)
        self.include_Q = include_Q
        return self
    end
end


function solve!(policy::ValueIterationPolicy, solver::ValueIterationSolver, pomdp::POMDP; verbose::Bool=false)

    # solver parameters
    max_iterations = solver.max_iterations
    tolerance = solver.tolerance
    discount_factor = discount(pomdp)

    # intialize the utility and Q-matrix
    util = policy.util
    qmat = policy.qmat
    include_Q = policy.include_Q
    pol = policy.policy 

    # pre-allocate the transtion distirbution and the interpolants
    dist = create_transition_distribution(pomdp)

    # initalize space
    sspace = states(pomdp)
    aspace = actions(pomdp)

    total_time = 0.0
    iter_time = 0.0

    # main loop
    for i = 1:max_iterations
        tic()
        residual = 0.0
        # state loop
        for (istate, s) in enumerate(domain(sspace))
            old_util = util[istate] # for residual 
            actions!(aspace, pomdp, s)
            max_util = -Inf
            # action loop
            # util(s) = R(s,a) + discount_factor * sum(T(s'|s,a)util(s')
            for (iaction, a) in enumerate(domain(aspace))
                transition!(dist, pomdp, s, a) # fills distribution over neighbors
                u = 0.0
                for j = 1:length(dist)
                    p = weight(dist, j)
                    sidx = index(dist, j)
                    u += p * util[sidx]
                end
                new_util = reward(pomdp, s, a) + discount_factor * u
                if new_util > max_util
                    max_util = new_util
                    pol[istate] = iaction
                end
                include_Q ? (qmat[istate, iaction] = new_util) : nothing
            end # actiom
            # update the value array
            util[istate] = max_util 
            diff = abs(max_util - old_util)
            diff > residual ? (residual = diff) : nothing
        end # state
        iter_time = toq()
        total_time += iter_time
        verbose ? println("Iteration : $i, residual: $residual, iteration run-time: $iter_time, total run-time: $total_time") : nothing
        residual < tolerance ? break : nothing
    end # main
    policy
end