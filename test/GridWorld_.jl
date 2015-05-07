
# gridworld mdp module

module GridWorld_

export GridWorldMDP, GWState, GWAction
export states, actions
export numStates, numActions
export reward, nextStates 
export i2s, s2i


using DiscreteMDPs
using GridInterpolations
using Iterators


import DiscreteMDPs.DiscreteMDP

import DiscreteMDPs.reward
import DiscreteMDPs.nextStates
import DiscreteMDPs.states
import DiscreteMDPs.actions
import DiscreteMDPs.numStates
import DiscreteMDPs.numActions

type GWState 
    x::Int64
    y::Int64
    bumped::Bool
    done::Bool
end

GWState(x::Vector) = GWState(x...)

type GWAction 
    dir::Symbol
end


type GridWorldMDP <: DiscreteMDP

    xSize::Int64
    ySize::Int64

    nStates::Int64
    stateIterator # iterator

    actions::Vector{GWAction}
    actionSymbols::Vector{Symbol}
    nActions::Int

    rewardPositions::Vector{Vector{Int64}}
    rewardValues::Vector

    endPositions::Vector

    discount::Float64

    tempPos::Vector
    tempState::GWState
    tempSub::Vector
    tempNextStates::Vector # state indices vector
    tempProbs::Vector # transition prob vector

    # step sizes for neighboring states
    xSteps::Vector
    ySteps::Vector

    sizes::Vector

    grid::RectangleGrid

    function GridWorldMDP(xSize::Int, ySize::Int, rewardPositions::Vector, rewardValues::Vector)

        self = new()

        nStates = xSize * ySize * 2 * 2
        stateIterator = product([1:xSize], [1:ySize], [false, true], [false, true])

        self.xSize = xSize
        self.ySize = ySize
        self.nStates = nStates

        self.actions = [GWAction(:east), GWAction(:west), GWAction(:north), GWAction(:south)]
        self.actionSymbols = [:east, :west, :north, :south]
        self.nActions = 4

        self.stateIterator = stateIterator 
        #self.states        = [GWState((s[1], s[2]), s[3], s[4]) for s in stateIterator]

        self.rewardPositions = rewardPositions 
        self.rewardValues    = rewardValues 

        # set all position with + reward as terminal 
        endPositions = Array(Vector{Int64}, 0)
        for i = 1:length(rewardValues)
            if rewardValues[i] > 0.0
                push!(endPositions, rewardPositions[i])
            end
        end
        self.endPositions = endPositions

        self.discount = 0.99

        # memory pre-allocation
        self.tempPos   = [1,1]
        self.tempState = GWState([1, 1, 1, 1])
        self.tempSub = [1, 1, 1, 1]
        self.tempNextStates = [1, 2, 3, 4]
        self.tempProbs = [0.25, 0.25, 0.25, 0.25]

        self.xSteps = [1, -1, 0, 0]
        self.ySteps = [0, 0, 1, -1]

        self.sizes = [xSize, ySize, 2, 2]

        self.grid = RectangleGrid([1.:xSize], [1.:ySize], [0.,1], [0.,1])

        return self
    end

end


function states(mdp::GridWorldMDP)
    return mdp.stateIterator
end

function actions(mdp::GridWorldMDP)
    return mdp.actions
end

function numStates(mdp::GridWorldMDP)
    return mdp.nStates
end

function numActions(mdp::GridWorldMDP)
    return mdp.nActions
end

function reward(mdp::GridWorldMDP, state::GWState, action::GWAction)
    r = 0.0
    x = state.x
    y = state.y
    p = [x,y]
    rewardPositions = mdp.rewardPositions
    rewardValues = mdp.rewardValues
    if !state.done
        if p in rewardPositions
            r += rewardValues[findin(rewardPositions, Array[p])[1]]
        end
        if state.bumped
            r -= 1.
        end
    end
    return r
end


function reward(mdp::GridWorldMDP, stateIdx::Int64, actionIdx::Int64)
    sizes = mdp.sizes
    # convert action index to action type
    a = mdp.actions[actionIdx]
    # convert state index to state type
    tempSub = mdp.tempSub
    ind2sub!(tempSub, sizes, stateIdx)
    s = mdp.tempState
    s.x = tempSub[1]
    s.y = tempSub[2]
    s.bumped = tempSub[3] - 1
    s.done = tempSub[4] - 1
    return reward(mdp, s, a)
end


function nextStates(mdp::GridWorldMDP, stateIdx::Int64, actionIdx::Int64)
    states = [1,1,1,1]

    tempSub = mdp.tempSub
    sizes = mdp.sizes
    p = mdp.tempPos

    ind2sub!(tempSub, sizes, stateIdx)
    rootX = tempSub[1]
    rootY = tempSub[2]
    rootB = tempSub[3]
    rootD = tempSub[4]

    tempState = mdp.tempState
    xSteps    = mdp.xSteps
    ySteps    = mdp.ySteps

    for i = 1:4
        xp = rootX + xSteps[i]
        yp = rootY + ySteps[i]
        p[1] = xp
        p[2] = yp
        tempSub[3] = rootB
        tempSub[4] = rootD
        if !inBounds(mdp, p)
            # bumped is true
            tempSub[1] = rootX
            tempSub[2] = rootY
            tempSub[3] = 2 
        else
            # otherwise move to the next location
            tempSub[1] = xp
            tempSub[2] = yp
            tempSub[3] = 1
        end
        if p in mdp.endPositions
            # done is true
            tempSub[4] = 2 
        end

        states[i] = sub2ind(sizes, tempSub)
    end

    probs = fill(0.1, 4)
    probs[actionIdx] = 0.7
    return states, probs
end


function nextStates(mdp::GridWorldMDP, state::GWState, action::GWAction)
    
    xs = state.x
    ys = state.y

    positions  = Array[[xs+1, ys], [xs-1, ys], [xs, ys+1], [xs,ys-1]]

    states = [GWState([positions[i], false, state.done]) for i = 1:4]

    for i = 1:4
        p = [states[i].x, states[i].y]
        if !inBounds(mdp, p)
            states[i].x = xs
            states[i].y = ys
            states[i].bumped = true
        end
        if p in mdp.endPositions
            states[i].done = true
        end
    end

    # 0.7 prob of moving in action dir, uniform across others
    aIdx = actionMap(action) 
    probs = fill(0.1, 4)
    probs[aIdx] = 0.7

    return states, probs
end

function inBounds(mdp::GridWorldMDP, x::Int64, y::Int64)
    if 1 <= x <= mdp.xSize && 1 <= y <= mdp.ySize
        return true
    end
    return false
end

function inBounds(mdp::GridWorldMDP, p::Vector)
    x = p[1]
    y = p[2]
    return inBounds(mdp, x, y)
end


function actionMap(a::GWAction)
    d = a.dir
    if d == :east
        return 1
    elseif d == :west
        return 2
    elseif d == :north
        return 3
    elseif d == :south
        return 4
    else
        return 0
    end
end

function i2s(mdp::GridWorldMDP, s::Int)
    x = ind2x(mdp.grid, s)
    return GWState(x[1], x[2], bool(x[3]), bool(x[4]))
end

function s2i(mdp::GridWorldMDP, s::GWState)
    xSize = mdp.xSize
    ySize = mdp.ySize
    xp = s.x
    yp = s.y
    idx = 1
    idx += (xp - 1) 
    idx += (yp - 1) * xSize
    if s.bumped && s.done
        idx += 3 * xSize * ySize
    elseif s.done
        idx += 2 * xSize * ySize
    elseif s.bumped
        idx += xSize * ySize
    else
        idx += 0
    end
    return idx
end


# not exported in julia base?
function ind2sub!{T<:Integer}(sub::Array{T}, dims::Array{T}, ind::T)
    ndims = length(dims)
    stride = dims[1]
    for i in 2:(ndims - 1)
        stride *= dims[i]
    end
    for i in (ndims - 1):-1:1
        rest = rem1(ind, stride)
        sub[i + 1] = div(ind - rest, stride) + 1
        ind = rest
        stride = div(stride, dims[i])
    end
    sub[1] = ind
    return
end

end # module
