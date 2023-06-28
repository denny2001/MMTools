% This code solves the gain-managed amplifier (GMNA).

close all; clearvars;

addpath('../../../../GMMNLSE algorithm/','../../../../user_helpers/');

%% Setup fiber parameterss
% Please find details of all the parameters in "load_default_GMMNLSE_propagate.m".
% Only necessary parameters are set here; otherwise, defaults are used.
sim.lambda0 = 1080e-9;
sim.f0 = 2.99792458e-4/sim.lambda0;
sim.gpu_yes = false;
sim.save_period = 0.1;
sim.num_photon_noise_per_band = 1;
sim.Raman_sponRS = true;

% -------------------------------------------------------------------------

% Gain fiber
sim_Gain = sim;
sim_Gain.gain_model = 2;
sim_Gain.progress_bar_name = 'Gain (6um)';
fiber_Gain.L0 = 3;

% Load default parameters like 
%
% loading fiber.betas and fiber.SR based on your multimode folder above
% sim.Raman_model = 1; Use isotropic Raman model
% sim.gain_model = 0; Don't use gain model = passive propagation
% sim.gpu_yes = true; Use GPU (default to true)

% ......
%
% Please check this function for details.
[fiber_Gain,sim_Gain] = load_default_GMMNLSE_propagate(fiber_Gain,sim_Gain,'single_mode'); % load default parameters for "fiber" and "sim"

%% Gain info
% Please find details of all the parameters in "gain_info.m" if not specified here.
% Note that the use of single spatial mode is different from multi-spatial modes.
% Activating "reuse_data" or "linear_oscillator_model" requires setting other parameters.
% Check the example or "gain_info.m".
gain_rate_eqn.cross_section_filename = 'Liekki Yb_AV_20160530.txt';
gain_rate_eqn.core_diameter = 6; % um
gain_rate_eqn.cladding_diameter = 125; % um
gain_rate_eqn.core_NA = 0.12;
gain_rate_eqn.absorption_wavelength_to_get_N_total = 920; % nm
gain_rate_eqn.absorption_to_get_N_total = 0.55; % dB/m
gain_rate_eqn.pump_wavelength = 976; % nm
gain_rate_eqn.copump_power = 0; % W
gain_rate_eqn.counterpump_power = 1.4; % W
gain_rate_eqn.reuse_data = false; % For a ring or linear cavity, the pulse will enter a steady state eventually.
                                  % If reusing the pump and ASE data from the previous roundtrip, the convergence can be much faster, especially for counterpumping.
gain_rate_eqn.linear_oscillator = false; % For a linear oscillator, there are pulses from both directions simultaneously, which will deplete the gain;
                                         % therefore , the backward-propagating pulses need to be taken into account.
gain_rate_eqn.t_rep = 1/15e6; % Assume 15 MHz here; s; the time required to finish a roundtrip (the inverse repetition rate of the pulse)
                             % This gain model solves the gain of the fiber under the steady-state condition; therefore, the repetition rate must be high compared to the lifetime of the doped ions.
gain_rate_eqn.tau = 840e-6; % lifetime of Yb in F_(5/2) state (Paschotta et al., "Lifetme quenching in Yb-doped fibers"); in "s"
gain_rate_eqn.export_N2 = true; % whether to export N2, the ion density in the upper state or not
gain_rate_eqn.ignore_ASE = true;
gain_rate_eqn.max_iterations = 50; % If there is ASE, iterations are required.
gain_rate_eqn.tol = 1e-5; % the tolerance for the above iterations
gain_rate_eqn.verbose = true; % show the information(final pulse energy) during iterations of computing the gain

%% Setup general parameters
Nt = 2^14; % the number of time points
time_window = 100; % ps
dt = time_window/Nt;
f = sim_Gain.f0+(-Nt/2:Nt/2-1)'/(Nt*dt); % THz
t = (-Nt/2:Nt/2-1)'*dt; % ps
c = 299792458; % m/s
lambda = c./(f*1e12)*1e9; % nm

% Precompute some parameters related to the gain to save the computational time
% Check "gain_info.m" for details.
gain_rate_eqn = gain_info( fiber_Gain,sim_Gain,gain_rate_eqn,ifftshift(lambda,1) );

%% Setup initial conditions
tfwhm = 0.1; % ps
total_energy = 1; % nJ

pulse_lambda0 = 1025e-9;
f_now = c/sim_Gain.lambda0*1e-12;
f_pulse = c/pulse_lambda0*1e-12;
freq_shift = f_pulse - f_now;
prop_output = build_MMgaussian(tfwhm, time_window, total_energy, 1, Nt, {'ifft',freq_shift});

%% Run the cavity simulation
if sim_Gain.gpu_yes
    reset(gpuDevice);
end

prop_output = GMMNLSE_propagate(fiber_Gain, prop_output, sim_Gain, gain_rate_eqn);

%% Finish the simulation and save the data
N2 = prop_output.N2;
pump = prop_output.Power.pump.forward;
output_field = prop_output.fields(:,:,end);

% -----------------------------------------------------------------
% Energy of the output field
energy = squeeze(sum(trapz(abs(prop_output.fields).^2,1),2)*prop_output.dt/10^3); % energy in nJ

[Strehl_ratio,dechirped_FWHM,transform_limited_FWHM,peak_power] = analyze_field( t,f,prop_output.fields(:,:,end),'Treacy-t',pi/6,1e-6 );

func = analyze_sim;
fig_gain = func.analyze_gain(prop_output.z,[],prop_output.Power.pump,squeeze(prop_output.N2));