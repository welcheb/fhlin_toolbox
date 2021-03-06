function C = get_result(Data, C, Misc);

% preprocessing steps for optimisation
% FORMAT [SEM, stats] = get_result(Data, SEM, xfix, Free, x0);
%_______________________________________________________________________
%
% get_result is a function that preprocesses matrices ConX containing
% unidirectional connections and ConY containing bidirectional (eg. residual
% variances). 
%
% Input Parameters: 
%	Data 		- see spm_sem.m
% 	SEM		- see spm_sem.m
% 	xfix		- 2 x n matrix with fixed values (see get_equ for specification)
%	Free		- see spm_sem.m
%	x0		- (optional) starting estimates for optimisation
%
% Output Parameters: 
% 	SEM		- updated SEM struct (see spm_sem.m)
%	stats		- contains fields chi_sq, p, df
%
% Called by		: spm_sem
%
% Routines called	: spm_chi2_plot	(plotting convergence)
%			: myads2	(optimisation proper)
%
%_______________________________________________________
% @(#)get_results.m	1.17 Christian Buechel 97/08/03


SEM  = C.SEM;
xfix = C.xfix;
Free = C.Free;
x0   = C.x0; 



% Define variables
%-----------------
nfree	 = max(Free(1,:));
nfree    = nfree - size(xfix,2);
observed = length([Data.useit]);



% Options for optimisation
%------------------------
options1     = [1,1e-5,1e-9];
options1(14) = 5000;
options1(17) = 0.001;
stopit       = [1e-5 20000 inf 0 1];


% Optimisation proper
%-------------------

if Misc.random 
    x0 = rand(size(x0));
end;

tic;
opt(1) = 1;
opt(2) = 1e-6;

alwayssearch = 0;

a = ver;
str = 'findstr([a.Name],''Optimization Toolbox'')';

if eval(str) & (~alwayssearch)
    disp('# using MatLab''s fminu');
    options = optimset;
    x = fminunc('myfit_c',x0,options,xfix,SEM,0);
    %x = fminu('myfit_c',x0,opt,[],xfix,SEM,0);
else
    disp('# using ads');
    x = myads2('myfit_c',x0,stopit,[],[],xfix,SEM,1);
end
toc

%Get residuals and fit index
%---------------------------
[F, SEM] = myfit_c(x,xfix,SEM,0);

SEM = mod_index(x, xfix, SEM);


% Calculate overall fit of the model
%----------------------------------
C.chi_sq = sum([SEM.df])*F;


C.df = 0;
for k=1:size(Data,2)
    observed = length(Data(k).useit);
    C.df     = C.df + observed * (observed+1) / 2;
end

C.df     = C.df - nfree;

if C.df > 0 
    C.p = 1-spm_Xcdf(C.chi_sq,C.df);
else
    C.p = 0;
end

C.SEM   = SEM;
C.x0    = x0;
C.RMSEA = sqrt((C.chi_sq-C.df)/sum([SEM.df])/C.df);
C.ECVI  = (C.chi_sq+2*nfree)/sum([SEM.df]);
C.Pars  = [];

 