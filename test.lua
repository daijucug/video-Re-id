require 'torch'
require 'nn'
require 'nngraph'
require 'ReIdModel'
require 'hdf5'
cmd = torch.CmdLine()
cmd:text()
cmd:text('test the model for reid')
cmd:text()
cmd:text('Options')

cmd:option('-model', 'trained_model.t7', 'path to the model to test/evaluate')
cmd:option('-input_prob_images', './reid_data/test_images/test_data1', 'path to probe images to test')
cmd:option('-input_gall_images', './reid_data/test_images/test_data2', 'path to gallery images to search')
cmd:option('-gpuid', 0, 'which gpu to use. -1 = use cpu')
cmd:option('-seed', 123, 'random seed')

cmd:text()

local opt = cmd:parse(arg)
torch.manualSeed(opt.seed)
torch.setdefaulttensortype('torch.FloatTensor')

if opt.gpuid >= 0 then
    require 'cutorch'
    require 'cunn'
    cutorch.manualSeed(opt.seed)
    cutorch.setDevice(opt.gpuid + 1)
end

local reid_net = torch.load(opt.model)
reid_net:evaluate()

print('load test images data')
local data1 = hdf5.open(opt.input_prob_images, 'r')
local imgs1 = data1:read('/imgs')
local index1 = data1:read('/index'):all()
local length1 = data1:read('/seq_length'):all()
local data2 = hdf5.open(opt.input_gall_images, 'r')
local imgs2 = data2:read('/imgs')
local index2 = data2:read('/index'):all()
local length2 = data2:read('/seq_length'):all()

local probe = {}
local gallery = {}

for i = 1,100 do
    local imgs_set_p = {}
    local imgs_set_g = {}
    for j = 0,15 do
        local ximg_p = imgs1:partial({index1[i]+j, index1[i]+j}, {1, 3}, {1, 128}, {1, 64})
        local ximg_g = imgs2:partial({index2[i]+j, index2[i]+j}, {1, 3}, {1, 128}, {1, 64})
        if length1[i] < (j+1)  then
            ximg_p = imgs1:partial({index1[i]+length1[i]-1, index1[i]+length1[i]-1}, {1, 3}, {1, 128}, {1, 64})
        end
        if length2[i] < (j+1) then
            ximg_g = imgs2:partial({index2[i]+length2[i]-1, index2[i]+length2[i]-1}, {1, 3}, {1, 128}, {1, 64})
        end

        table.insert(imgs_set_p, ximg_p)
        table.insert(imgs_set_g, ximg_g)
    end
    table.insert(probe, imgs_set_p)
    table.insert(gallery, imgs_set_g)
end


if opt.gpuid >= 0 then
    for i = 1, 100 do
        for j = 1, 16 do
            probe[i][j] = probe[i][j]:cuda()
            gallery[i][j] = gallery[i][j]:cuda()
        end
    end
end


local probe_feat = {}
local gall_feat = {}

for i = 1, 100 do
    local feat = reid_net:forward({probe[i], gallery[i]})
    local feat_p = feat[1][1]
    local feat_g = feat[1][2]
    table.insert(probe_feat, feat_p)
    table.insert(gall_feat, feat_g)
end

for r = 1, 20 do
    local acc = 0
    local count = 0
    for i = 1, 100 do
        local p_feat = probe_feat[i]
        local dist = torch.zeros(100)
        dist:typeAs(p_feat)
        for j = 1, 100 do
            local g_feat = gall_feat[j]
            local d = torch.pow((torch.sum(torch.pow((p_feat - g_feat), 2))), 0.5)
            dist[j] = d
        end
        local dist, sort = torch.sort(dist)
        for s = 1,r do
            if sort[s] == i then
                count = count + 1
                break
            end
        end
    end
    
    print(string.format('there are %d persons ared corrected ideificated in test', count))
    acc = acc + count/100
    
    print(string.format('the accuracy when R = %d is %f', r, acc))
end




