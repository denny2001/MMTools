% This code runs the single-mode Yb-doped fiber amplifier with the gain 
% rate equation for copumping and counterpumping.
%
% This shows that copumping generates a pulse with higher nonlinear phase 
% because the pulse propagates with a high-energy state for a longer period
% of time compared to counterpumping.
% However, they have almost the same output pulse energy.

clearvars; close all;

addpath('../../GMMNLSE algorithm/','../../user_helpers/');

%% Gain info
gain_rate_eqn.cross_section_filename = 'Liekki Yb_AV_20160530.txt';
gain_rate_eqn.reuse_data = false; % For a ring or linear cavity, the pulse will enter a steady state eventually.
                                  % If reusing the pump and ASE data from the previous roundtrip, the convergence can be much faster, especially for counterpumping.
gain_rate_eqn.linear_oscillator = false; % For a linear oscillator, there are pulses from both directions simultaneously, which will deplete the gain;
                                         % therefore, the backward-propagating pulses need to be taken into account.
gain_rate_eqn.core_diameter = 6; % um
gain_rate_eqn.cladding_diameter = 125; % um
gain_rate_eqn.core_NA = 0.12;
gain_rate_eqn.absorption_wavelength_to_get_N_total = 920; % nm
gain_rate_eqn.absorption_to_get_N_total = 0.55; % dB/m
gain_rate_eqn.pump_wavelength = 976; % nm
gain_rate_eqn.t_rep = 1/15e6; % assume 15 MHz here; s; the time required to finish a roundtrip (the inverse repetition rate of the pulse)
                              % This gain model solves the gain of the fiber under the steady-state condition; therefore, the repetition rate must be high compared to the lifetime of the doped ions.
gain_rate_eqn.tau = 840e-6; % lifetime of Yb in F_(5/2) state (Paschotta et al., "Lifetme quenching in Yb-doped fibers"); in "s"
gain_rate_eqn.export_N2 = true; % whether to export N2, the ion density in the upper state or not
gain_rate_eqn.ignore_ASE = false;
gain_rate_eqn.max_iterations = 10; % If there is ASE, iterations are required.
gain_rate_eqn.tol = 1e-5; % the tolerance for the iteration
gain_rate_eqn.verbose = true; % show the information(final pulse energy) during iterations of computing the gain

% case 1: copumping
gain_rate_eqn_copumping = gain_rate_eqn;
gain_rate_eqn_copumping.copump_power = 1; % W
gain_rate_eqn_copumping.counterpump_power = 0; % W

% case 2: counterpumping
gain_rate_eqn_counterpumping = gain_rate_eqn;
gain_rate_eqn_counterpumping.copump_power = 0; % W
gain_rate_eqn_counterpumping.counterpump_power = 1; % W

%% Field and simulation parameters
time_window = 50; % ps
N = 2^12; % the number of time points
dt = time_window/N;
t = (-N/2:N/2-1)'*dt; % ps

fiber.L0 = 1; % m; the length of the gain fiber
save_num = 50; % the number of saved data
sim.save_period = fiber.L0/save_num;
%sim.progress_bar = false;
sim.lambda0 = 1030e-9; % central wavelength; in "m"
sim.gpu_yes = false;

sim.gain_model = 2; % use rate-equation-gain model

% Load default parameters like 
%
% loading fiber.betas and fiber.SR based on your multimode folder above
% sim.Raman_model = 1; Use isotropic Raman model
% sim.gain_model = 0; Don't use gain model = passive propagation
% sim.gpu_yes = true; Use GPU (default to true)
% ......
%
% Please check this function for details.
[fiber,sim] = load_default_GMMNLSE_propagate(fiber,sim);

%% Initial pulse
total_energy = 0.1; % nJ
tfwhm = 1; % ps
input_field = build_MMgaussian(tfwhm, time_window, total_energy, 1, N);
input_field.Power.ASE.forward = zeros(N,1);
input_field.Power.ASE.backward = zeros(N,1);

%% Gain parameters
% Precompute some parameters related to the gain to save the computational time
% Check "gain_info.m" for details..
f = ifftshift( (-N/2:N/2-1)'/N/dt + sim.f0 ); % in the order of "omegas" in the "GMMNLSE_propagate.m"
c = 299792.458; % nm/ps;
lambda = c./f; % nm

% case 1: copumping
gain_rate_eqn_copumping = gain_info( fiber,sim,gain_rate_eqn_copumping,lambda );
% case 2: counterpumping
gain_rate_eqn_counterpumping = gain_info( fiber,sim,gain_rate_eqn_counterpumping,lambda );

gain_rate_eqn = {gain_rate_eqn_copumping,gain_rate_eqn_counterpumping};

%% Propagation
t_end = zeros(1,2);
model_name = {'copumping','counterpumping'};
output_field = cell(1,2);
for i = 1:2
    output_field{i} = GMMNLSE_propagate(fiber,input_field,sim,gain_rate_eqn{i});
    t_spent = datevec(output_field{i}.seconds/3600/24);
    fprintf('Running time for %s: %2u:%3.1f\n',model_name{i},t_spent(5),t_spent(6));
end

%% Plot results
% nonlinear phase
nonlinear_phase_copumping = accumulated_nonlinear_phase(fiber.L0,1/fiber.SR,sim.f0,output_field{1}.fields,output_field{1}.z,output_field{1}.dt);
nonlinear_phase_counterpumping = accumulated_nonlinear_phase(fiber.L0,1/fiber.SR,sim.f0,output_field{2}.fields,output_field{2}.z,output_field{2}.dt);
fprintf('nonlinear phase (copumping): %6.4f\n',nonlinear_phase_copumping);
fprintf('nonlinear phase (counterpumping): %6.4f\n',nonlinear_phase_counterpumping);

energy_copumping   = permute(sum(trapz(abs(output_field{1}.fields).^2),2)*dt/1e3,[3 2 1]);
energy_counterpumping = permute(sum(trapz(abs(output_field{2}.fields).^2),2)*dt/1e3,[3 2 1]);

% Energy
distance = (0:save_num)*sim.save_period;
figure;
plot(distance,[energy_copumping energy_counterpumping]);
legend('copumping','counterpumping');
xlabel('Propagation length (m)');
ylabel('Energy (nJ)');
title('Energy');

c = 299792458e-12; % m/ps
f = (-N/2:N/2-1)'/N/dt+c/sim.lambda0;
lambda = c./f*1e9;

c = 299792.458; % nm/ps
factor = c./lambda.^2; % change the spectrum from frequency domain into wavelength domain

% -------------------------------------------------------------------------
% copumping
% -------------------------------------------------------------------------
% Field
figure;
subplot(2,1,1);
plot(t,abs(output_field{1}.fields(:,:,end)).^2);
xlabel('Time (ps)');
ylabel('Power (W)');
title('The final output field of YDFA (copumping)');

% Spectrum
subplot(2,1,2);
plot(lambda,abs(fftshift(ifft(output_field{1}.fields(:,:,end)),1)).^2.*factor);
xlabel('Wavelength (nm)');
ylabel('PSD (a.u.)');
title('The final output spectrum of YDFA (copumping)');
xlim([1010 1050]);

% -------------------------------------------------------------------------
% counterpumping
% -------------------------------------------------------------------------
% Field
figure;
subplot(2,1,1);
plot(t,abs(output_field{2}.fields(:,:,end)).^2);
xlabel('Time (ps)');
ylabel('Power (W)');
title('The final output field of YDFA (counterpumping)');

% Spectrum
subplot(2,1,2);
plot(lambda,abs(fftshift(ifft(output_field{2}.fields(:,:,end)),1)).^2.*factor);
xlabel('Wavelength (nm)');
ylabel('PSD (a.u.)');
title('The final output spectrum of YDFA (counterpumping)');
xlim([1010 1050]);

%% Save results
save('SM_YDFA_compare_co_and_counterpumping.mat');