function [gpuDevice_Device,...
          cuda_SRSK,num_operations,...
          cuda_MPA_psi_update,...
          cuda_mypagemtimes] = setup_stepping_kernel(sim,Nt,num_modes,...
                                                     rmc_yes)
%SETUP_STEPPING_KERNEL It sets cuda for computing sums of SR and SK terms.

% Use the specified GPU
% This needs to run at the beginning; otherwise, the already-stored values
% in GPU will be unavailable in a new GPU if the GPU device is switched.
try
    gpuDevice_Device = gpuDevice(sim.gpuDevice.Index); % use the specified GPU device
catch
    error('Please set the GPU you''re going to use by setting "sim.gpuDevice.Index".');
end

% For no gain, single-mode-Gaussian gain, or rate-eqn gain, use the normal cuda file
% For the multimode-Gaussian-gain model, use the slightly modified cuda file
if sim.gain_model == 1 && length(sim.midx) ~= 1 % multimode-Gaussian-gain model
    gain_str = '_MMGaussianGain';
else % no gain, single-mode-Gaussian gain, rate-eqn gain
    gain_str = '';
end

% Polarization modes
if sim.scalar
    polar_str = '';
else % polarized fields
    polar_str = '_with_polarization';
end

% Nonlinear term
SRSK_filename = ['GMMNLSE_nonlinear_sum' gain_str polar_str];

switch SRSK_filename
    case 'GMMNLSE_nonlinear_sum'
        num_operations = 2;
    case {'GMMNLSE_nonlinear_sum_with_polarization','GMMNLSE_nonlinear_sum_MMGaussianGain'}
        num_operations = 3;
    case 'GMMNLSE_nonlinear_sum_MMGaussianGain_with_polarization'
        num_operations = 4;
end

% The number of blocks is set based on the total number of threads
if isequal(sim.step_method,'MPA')
    M = sim.MPA.M+1;
else % RK4IP
    M = 1;
end

% Kernal for computing the nonlinear term of GMMNLSE
cuda_SRSK = setup_kernel_SRSK(SRSK_filename,sim.cuda_dir_path,Nt,M,num_operations,num_modes^2);

% Kernal for updating psi in MPA stepping algorithm
if isequal(sim.step_method,'MPA')
    cuda_MPA_psi_update = setup_kernel_MPA_coeff('MPA_psi_update',sim.cuda_dir_path,Nt,M,num_modes);
else
    cuda_MPA_psi_update = [];
end

% Kernal for random mode coupling
if ~exist('rmc_yes','var')
    rmc_yes = false;
end
if rmc_yes
    cuda_mypagemtimes = setup_kernel_mypagemtimes('mypagemtimes',sim.cuda_dir_path,Nt,M,num_modes);
else
    cuda_mypagemtimes = []; % dummy output argument
end

end

