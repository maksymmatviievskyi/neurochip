import numpy as np
import torch
import torch.nn as nn

dtype = torch.float
device = torch.device("cpu")

netshape = (36, 64, 5)

class snn(nn.Module):
     def __init__(self, decayShift, threshold, resetV, layers):
        super().__init__()
        self.decayShift = decayShift
        self.threshold = threshold
        self.resetV = resetV
        self.layers = layers

        self.W = nn.ParameterList(
            nn.Parameter(torch.zeros(next_size, size))
            for size, next_size in zip(layers, layers[1:])
        )
        self.init_weights(fire_rate=0.2, std_gain=2.0, mean_gain=2.0)

     def init_weights(self, fire_rate, std_gain, mean_gain):
        # gaussian, scaled relative to threshold using the no-reset steady state:
        # E[v]   = fan_in * p * mu / (1 - alpha)        -> mean_gain * threshold
        # std(v) = sqrt(fan_in * p) * sigma / sqrt(1 - alpha^2) -> std_gain * threshold
        alpha = 1 - 2 ** -self.decayShift
        for w in self.W:
            fan_in = w.shape[1]
            mu = mean_gain * self.threshold * (1 - alpha) / (fan_in * fire_rate)
            sigma = std_gain * self.threshold * (1 - alpha ** 2) ** 0.5 / (fan_in * fire_rate) ** 0.5
            nn.init.normal_(w, mean=mu, std=sigma)

     def lif(self, s, v, w):
        v = v - v / 2 ** self.decayShift + w @ s
        spikes = (v >= self.threshold).float()
        v = torch.where(spikes > 0, torch.zeros_like(v), v)
        return spikes, v

     def forward(self, s):
        current = s
        voltages = [
            torch.zeros(size, dtype=torch.float32)
            for size in self.layers[1:]
        ]
        outputs = []

        for i, w in enumerate(self.W):
            spikes, voltages[i] = self.lif(current, voltages[i], w)
            outputs.append(spikes)
            current = spikes

        return outputs
