% Example propagation in GRIN fiber, at a relatively low power.
% You can use this as a starting point for more specific simulations
%

close all; clearvars;

addpath('../../../GMMNLSE algorithm/','../../../user_helpers/'); % MATLAB needs to know where the propagate files are located

%% Setup fiber parameters
num_modes = 6; % The number of modes to be simulated. 1-~8 will be "very fast", 10-20 will get slower but it still works. More than 20 modes have not been tested

% Multimode parameters
fiber.MM_folder = '../../../Fibers/OM4_wavelength1030nm/';
fiber.betas_filename = 'betas.mat';
fiber.S_tensors_filename = ['S_tensors_' num2str(num_modes) 'modes.mat'];

fiber.L0 = 0.15; % Fiber length in m

fiber.dB_gain = 100; % the small-signal dB gain
fiber.saturation_intensity = 150; % J/m^2

%% Setup simulation parameters
c = 299792458*1e-12; % m/ps
wavelength_range = [0.7,2]*1e-6; % m
Nt = 2^11;
[f0,f_range,time_window,dt] = find_tw_f0(c./wavelength_range,Nt);
sim.f0 = f0; % central pulse wavelength (m)

sim.gain_model = 1; % Gaussian gain

[fiber,sim] = load_default_GMMNLSE_propagate(fiber,sim,'multimode');

%% Setup initial conditions
tfwhm = 0.05; % ps, FWHM of the initial pulse.
total_energy = 17.04; % nJ, total energy of the initial pulse. By convension this is the total energy in all modes

% This is a helper function to build an evently distributed gaussian
% initial MM pulse
pump_wavelength = 1030e-9; % m
freq_shift = c/pump_wavelength - sim.f0;
initial_condition = build_MMgaussian(tfwhm, time_window, total_energy, num_modes, Nt, {'ifft',freq_shift});

%% Run the propagation
prop_output = GMMNLSE_propagate(fiber, initial_condition, sim); % This actually does the propagation

% The output of the propagation is a struct with:
% prop_output.fields = MM fields at each save point and the initial condition. The save points will be determined by sim.save_period, but the initial condition will always be saved as the first page.
% prop_output.dt = dt
% prop_output.seconds = total execution time in the main loop
% prop_output.full_iterations_hist (if using MPA) = a histogram of the
% number of iterations required for convergence

save('OM4_lowpower_single_gpu_mpa', 'prop_output', 'fiber', 'sim'); % Also save the information about the propagation
disp(prop_output.seconds);

%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Plot the results
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%

Nt = size(prop_output.fields, 1); % Just in case we're loaded from a save


%% Plot the time domain
figure();
I_time = abs(prop_output.fields(:, :, end).^2);
t = (-Nt/2:Nt/2-1)*(prop_output.dt);
tlim = 1;

subplot(1, 2, 1);
plot(t, I_time),axis tight, grid on
ylabel('Power (W)')
xlabel('Time (ps)')
xlim([-tlim, tlim])

%% Plot the frequency domain
I_freq = abs(ifftshift(ifft(prop_output.fields(:, :, end)))).^2;
f = sim.f0+(-Nt/2:Nt/2-1)/(prop_output.dt*Nt); % ps
flim = 60;

subplot(1, 2, 2);
plot(f, I_freq),axis tight, grid on
ylabel('PSD (a.u.)')
xlabel('Frequency (THz)')
xlim([sim.f0-flim, sim.f0+flim])

%% Load the spatial modes and plot the full spatial field

% Load the modes
prefix = '../../../Fibers/OM4_wavelength1030nm';
Nx = 400; % The number of spatial grid points that the modes use
mode_profiles = zeros(Nx, Nx, num_modes);
radius = '25'; % Used for loading the file
lambda0 = '1030'; % Used for loading the file
for ii = 1:num_modes
   name = [prefix, '/mode',int2str(ii),'wavelength', lambda0, '.mat'];
   load(name, 'phi');
   mode_profiles(:, :, ii) = phi; % Save the modes
   disp(['Loaded mode ', int2str(ii)])
end
mode_profiles = mode_profiles./sqrt(sum(sum(abs(mode_profiles).^2,1),2));
load(name, 'x');
x = (x-mean(x))*1e-6; % The spatial coordinates along one dimension
dx = x(2)-x(1);

% Downsample in space to reduce memory usage
factor = 8;
dx = dx*factor;
mode_profiles_sampled = zeros(Nx/factor, Nx/factor, num_modes);
for ii = 1:num_modes
    mode_profiles_sampled(:, :, ii) = downsample(downsample(mode_profiles(:, :, ii), factor)', factor)';
end
x = downsample(x, factor);
Nx = Nx/factor;
[X, Y] = meshgrid(x, x);

% Build the field from the modes and the spatial profiles
E_txy = recompose_into_space(sim.gpu_yes, mode_profiles_sampled, prop_output.fields(:, :, end), sim.cuda_dir_path);
A0 = permute(sum(abs(E_txy).^2, 1)*prop_output.dt/1e12, [2 3 1]); % Integrate over time to get the average spatial field

% Plot the spatial field
figure();
h = pcolor(X*1e6, Y*1e6, A0);
h.LineStyle = 'none';
colorbar;
axis square;
xlabel('x (um)');
ylabel('y (um)');
xlim([-60, 60]);
ylim([-60, 60]);