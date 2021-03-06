local torch = require 'torch'
local optim = require 'optim'
local image = require 'image'
local cuda = pcall(require, 'cutorch')
local mnist = require 'mnist'
local path = require 'paths'
local gnuplot = require 'gnuplot'

print('Setting up')
torch.setheaptracking(true)
-- torch.setdefaulttensortype('torch.FloatTensor')
torch.manualSeed(1)
if cuda then
  require 'cunn'
  cutorch.manualSeed(torch.random())
end

local cmd = torch.CmdLine()
cmd:option('-learningRate', 0.001, 'Learning rate')
cmd:option('-sparsity', 4, 'K-sparsity')
cmd:option('-epochs', 50, 'Training epochs')
cmd:option('-patch_size', 14, 'Patch size')
local opt = cmd:parse(arg)

local testset = mnist.testdataset().data:double():div(255)

local trainset = mnist.traindataset().data:double():div(255)

-- local validationset = mnist.traindataset().data[{{50001, 60000}}]:double():div(255)

local Ntrain = trainset:size(1)
local Ntest = testset:size(1)
-- local Nvalid = validationset:size(1)

if cuda then
  trainset = trainset:cuda()
  validationset = validationset:cuda()
end

print(type(trainset))
print(trainset:size())

local AE = require 'grid_model'
AE:createAutoencoder(trainset, opt.sparsity, opt.patch_size)
local model = AE.autoencoder

if cuda then
  model:cuda()
end

local criterion = nn.BCECriterion()

if cuda then
  criterion:cuda()
end

local sgd_params = {
  learningRate = opt.learningRate
}

theta, dl_dx = model:getParameters()
weights, gradWeights = model:parameters()

local abs_mean_gradient_l1, abs_mean_gradient_l2 = {}, {}
local abs_mean_gradient_l3 = {}

local x

local feval = function(params)
  if theta ~= params then theta:copy(params) end
  dl_dx:zero()

  local Xhat = model:forward(x)
  local loss = criterion:forward(Xhat, x)
  local gradLoss = criterion:backward(Xhat, x)
  model:backward(x, gradLoss)

  return loss, dl_dx
end

local __, loss

local losses = {}

step = function(batch_size)
  local current_loss = 0
  local count = 0
  batch_size = batch_size or 200

  for t = 1, Ntrain, batch_size do
    x = trainset:narrow(1, t, batch_size)

    __, loss = optim.adam(feval, theta, sgd_params)
    count = count + 1
    current_loss = current_loss + loss[1]
    losses[#losses + 1] = loss[1]
  end

  abs_mean_gradient_l1[#abs_mean_gradient_l1 + 1] = torch.mean(torch.abs(gradWeights[1]))
  -- abs_mean_gradient_l2[#abs_mean_gradient_l2 + 1] = torch.mean(torch.abs(gradWeights[9]))
  -- abs_mean_gradient_l3[#abs_mean_gradient_l3 + 1] = torch.mean(torch.abs(gradWeights[17]))

  -- print("layer1")
  -- print(torch.mean(torch.abs(gradWeights[1])))
  -- print(torch.mean(torch.abs(gradWeights[3])))
  -- print(torch.mean(torch.abs(gradWeights[5])))
  -- print(torch.mean(torch.abs(gradWeights[7])))
  --
  -- print("layer2")
  -- print(gradWeights[9]:norm(1))
  -- print(gradWeights[11]:norm(1))
  -- print(gradWeights[13]:norm(1))
  -- print(gradWeights[15]:norm(1))
  --
  -- print("layer3")
  -- print(gradWeights[17]:norm(1))
  -- print(gradWeights[19]:norm(1))
  -- print(gradWeights[21]:norm(1))
  -- print(gradWeights[23]:norm(1))
  --
  -- print("layer4")
  -- print(gradWeights[25]:norm(1))
  -- print(gradWeights[27]:norm(1))
  -- print(gradWeights[29]:norm(1))
  -- print(gradWeights[31]:norm(1))

  return current_loss / count
end


-- eval = function(batch_size)
--   local count = 0
--   local l = 0
--   batch_size = batch_size or 200
--
--   for i = 1, Nvalid, batch_size do
--     x = validationset:narrow(1, i, batch_size)
--     local Xhat = model:forward(x)
--     local current_loss = criterion:forward(Xhat, x)
--     l = l + current_loss
--     count = count + 1
--   end
--
--   return l / count
-- end

train = function()
  local last_error = 0
  local increasing = 0
  local threshold = 1
  for i = 1, opt.epochs do
    local loss = step()
    print(string.format('Epoch: %d current loss: %4f', i, loss))
    -- local error = eval()
    -- print(string.format('Error on the validation set: %4f', error))
    -- if error > last_error then
    --   if increasing > threshold then break end
    --   increasing = increasing + 1
    -- else
    --   increasing = 0
    -- end
    -- last_error = error
  end
end

-- print(model)

-- saving model
modelName = '/grid_training.net'
filename = path.cwd() .. modelName

if path.filep(filename) then
  print("Model exists!")
  model = torch.load(filename)
  print(model)
else
  print("Model does not exist! Needs to be trained first.")
  train()
  torch.save(filename, model)
end

if itorch then
  itorch.image(model:get(2).weight)
end

local numberOfPatches = math.floor(trainset:size(2) / opt.patch_size)

for i = 1, numberOfPatches * numberOfPatches do
  eweight = model:get(1):get(2):get(i):get(2).weight
  -- dweight = model:get(1):get(5):get(i):get(2).weight
  -- cweight = model:get(1):get(8):get(i):get(2).weight
  -- dweight = model:get(2):get(1):get(i):get(1).weight
  -- dweight = dweight:transpose(1,2):unfold(2, opt.patch_size, opt.patch_size)
  -- dweight = dweight:unfold(2, opt.patch_size, opt.patch_size)
  eweight = eweight:unfold(2, opt.patch_size, opt.patch_size)
  -- cweight = cweight:unfold(2, opt.patch_size, opt.patch_size)

  -- ce = image.toDisplayTensor{input=cweight,
  --                            padding=2,
  --                            nrow=math.floor(math.sqrt(opt.patch_size * opt.patch_size)),
  --                            symmetric=true}
  -- dd = image.toDisplayTensor{input=dweight,
  --                            padding=2,
  --                            nrow=math.floor(math.sqrt(opt.patch_size * opt.patch_size)),
  --                            symmetric=true}
  de = image.toDisplayTensor{input=eweight,
                             padding=2,
                             nrow=math.floor(math.sqrt(opt.patch_size * opt.patch_size)),
                             symmetric=true}


  if itorch then
    print('Decoder filters')
    itorch.image(dd)
    print('Encoder filters')
    itorch.image(de)
  else
    print('run in itorch for visualization')
  end

  image.save(path.cwd() .. '/grid_decoder/filters_enc_l1_' .. i .. '.jpg', de)
  -- image.save(path.cwd() .. '/grid_encoder/filters_enc_l2_' .. i .. '.jpg', dd)
  -- image.save(path.cwd() .. '/grid_layer_3/filters_enc_l3_' .. i .. '.jpg', ce)
end

-- plotting mean absolute gradients
local plots = {{'Mean absolute gradient layer 1', torch.linspace(1, #abs_mean_gradient_l1, #abs_mean_gradient_l1), torch.Tensor(abs_mean_gradient_l1), '-'}}
-- plots[#plots + 1] = {'Mean absolute gradient layer 2', torch.linspace(1, #abs_mean_gradient_l2, #abs_mean_gradient_l2), torch.Tensor(abs_mean_gradient_l2), '-'}
-- plots[#plots + 1] = {'Mean absolute gradient layer 3', torch.linspace(1, #abs_mean_gradient_l3, #abs_mean_gradient_l3), torch.Tensor(abs_mean_gradient_l3), '-'}

gnuplot.pngfigure(path.cwd() .. '/plots/MeanAbsGradientsl.png')
gnuplot.plot(table.unpack(plots))
gnuplot.ylabel('Mean Absolute value')
gnuplot.xlabel('Epoch #')
gnuplot.plotflush()

-- plotting loss function
local plot_loss = {'Loss', torch.linspace(1, #losses, #losses), torch.Tensor(losses), '-'}
gnuplot.pngfigure(path.cwd() .. '/plots/Losses.png')
gnuplot.plot(table.unpack(plot_loss))
gnuplot.ylabel('Loss')
gnuplot.xlabel('Batch #')
gnuplot.plotflush()
