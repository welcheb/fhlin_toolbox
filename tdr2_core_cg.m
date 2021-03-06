function [recon,b,delta]=tdr2_core_cg(varargin);
%
%	tdr2_core_cg		perform SENSE reconstruction using conjugated gradient method
%
%
%	[recon,b,delta]=tdr2_core_cg('Y',Y,'S',S,'C',C,'K',K,'flag_display',1);
%
%	INPUT:
%	Y: input data of [n_PE, n_FE, n_chan].
%		n_PE: # of phase encoding
%		n_FE: # of frequency encoding
%		n_chan: # of channel
%	S: coil sensitivity maps of [n_PE, n_FE, n_chan].
%		n_PE: # of phase encoding
%		n_FE: # of frequency encoding
%		n_chan: # of channel
%	C: noise covariance matrix of [n_chan, n_chan].
%		n_chan: # of channel
%	K: 2D k-space sampling matrix with entries of 0 or 1 [n_PE, n_FE].
%		n_PE: # of phase encoding
%		n_FE: # of frequency encoding
%		"0" indicates the correponding entries are not sampled in accelerated scan.
%		"1" indicates the correponding entries are sampled in accelerated scan.
%	'flag_display': value of either 0 or 1
%		It indicates of debugging information is on or off.
%
%	OUTPUT:
%	recon: 2D un-regularized SENSE reconstruction [n_PE, n_PE].
%		n_PE: # of phase encoding steps
%		n_FE: # of frequency encoding steps
%	b: history of all 2D un-regularized SENSE reconstruction [n_PE, n_PE, n_CG].
%		n_PE: # of phase encoding steps
%		n_FE: # of frequency encoding steps
%		n_CG: # of CG iteration
%	delta: history of all errors in CG iteration [n_CG, 1]
%		n_CG: # of CG iteration
%
%---------------------------------------------------------------------------------------
%	Fa-Hsuan Lin, Athinoula A. Martinos Center, Mass General Hospital
%
%	fhlin@nmr.mgh.harvard.edu
%
%	fhlin@mar. 18, 2005

S=[];
C=[];
Y=[];

K=[];
G=[];
P=[];

X0=[];



flag_display=0;

flag_reg=0;
flag_reg_g=0;

flag_unreg=1;
flag_unreg_g=0;

flag_regrid_direct=0;   %direct regrid by nearest neighbor searching
flag_regrid_kb=1;       %Kaiser Bessel function regridding

flag_debug=0;



iteration_max=[];

epsilon=[];



for i=1:floor(length(varargin)/2)
    option=varargin{i*2-1};
    option_value=varargin{i*2};
    switch lower(option)
        case 's'
            S=option_value;
        case 'c'
            C=option_value;
        case 'p'
            P=option_value;
        case 'y'
            Y=option_value;
        case 'k'
            K=option_value;
        case 'g'
            G=option_value;
        case 'x0'
            X0=option_value;
        case 'lambda'
            lambda=option_value;
        case 'flag_display'
            flag_display=option_value;
        case 'flag_reg'
            flag_reg=option_value;
        case 'flag_reg_g'
            flag_reg_g=option_value;
        case 'flag_unreg'
            flag_unreg=option_value;
        case 'flag_unreg_g'
            flag_unreg_g=option_value;
        case 'flag_regrid_direct'
            flag_regrid_direct=option_value;
        case 'flag_regrid_kb'
            flag_regrid_kb=option_value;
        case 'iteration_max'
            iteration_max=option_value;
        case 'epsilon'
            epsilon=option_value;
        case 'flag_debug'
            flag_debug=option_value;
        otherwise
            fprintf('unknown option [%s]!\n',option);
            fprintf('error!\n');
            return;
    end;
end;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% prepare gradient information

n_freq=size(Y,2);
n_phase=size(Y,1);
%setup 2D gradient
if(isempty(G))
    [grid_freq,grid_phase]=meshgrid([-floor(n_freq/2):ceil(n_freq/2)-1],[-floor(n_phase/2) :1:ceil(n_phase/2)-1]);
else
    grid_freq=G{1};
    grid_phase=G{2};
    grid_freq=fmri_scale(grid_freq,ceil(n_freq/2)-1,-floor(n_freq/2));
    grid_phase=fmri_scale(grid_phase,ceil(n_phase/2)-1,-floor(n_phase/2));
end;
%preparation for regridding
[xgrid_freq,xgrid_phase]=meshgrid([-floor(n_freq/2):ceil(n_freq/2)-1],[-floor(n_phase/2) :1:ceil(n_phase/2)-1]);
regrid_kernel=[];
regrid_kernel_inv=[];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% intensity correction

I=zeros(size(S,1),size(S,2));
for i=1:size(S,3)
    I=I+abs(S(:,:,i)).^2;
end;
I=1./sqrt(I);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for i=1:size(Y,3)

    %Density correction here
    % .... do nothing

    % FT1
    %temp(:,:,i)=fftshift(fft2(fftshift(Y(:,:,i))));
    Temp=fftshift(ifft2(fftshift(Y(:,:,i))));

    if(flag_regrid_direct)
        idx=sub2ind([n_phase,n_freq],ceil(grid_phase(:))+n_phase/2+1,ceil(grid_freq(:))+n_freq/2+1);
        recon=reshape(Temp(idx),[n_phase,n_freq]);
    elseif(flag_regrid_kb)
        x_in=[xgrid_freq(:),xgrid_phase(:)];
        y_in=Temp(:);
        x_out=[grid_freq(:),grid_phase(:)];

        if(isempty(regrid_kernel)|isempty(regrid_kernel_inv))
            fprintf('regridding...\n');
            [recon, regrid_kernel,regrid_kernel_inv]=etc_regridn(x_in,y_in,x_out,'flag_inv',0);
            recon=reshape(recon,[n_phase,n_freq]);
        else
            [recon, regrid_kernel,regrid_kernel_inv]=etc_regridn(x_in,y_in,x_out,'kernel',regrid_kernel,'kernel_inv',regrid_kernel_inv,'flag_inv',0);
            recon=reshape(recon,[n_phase,n_freq]);
        end;
    end;
    temp(:,:,i)=recon;


    % S' (complex-conjugated sensitivity)
    temp(:,:,i)=temp(:,:,i).*conj(S(:,:,i));
end;
%intensity correction here
a=sum(temp,3).*I;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

convergence=0;
iteration_idx=2;

if(isempty(X0))
    b(:,:,1)=zeros(size(Y,1),size(Y,2));
else
    b(:,:,1)=X0;
end;


p(:,:,1)=a;
r(:,:,1)=a;


if(isempty(epsilon))
    epsilon=sum(abs(Y(:)).^2)./50./size(Y,3);
    %epsilon=sum(abs(Y(:)).^2)./1000./size(Y,3);
    if(flag_display)
        fprintf('automatic setting error check in CG to [%2.2e]\n',epsilon);
    end;
end;



if(isempty(iteration_max))

    iteration_max=round(size(K,1)/3);

    if(flag_display)
        fprintf('automatic setting maximum CG iteration to [%d]\n',iteration_max);
    end;
end;


%TDR preparation
gamma=267.52e6;     %gyromagnetic ratio; rad/Tesla/s
FOV_freq=256e-3;        %m
FOV_phase=256e-3;        %m
delta_time_freq=40e-6;      %sampling time (read-out): s
time_phase=4e-3;            %duration of phase encoding gradient: s
grad_max_freq=2.*pi./gamma./FOV_freq./delta_time_freq;     %gradient (read-out): T/m
grad_delta_phase=2.*pi./gamma./FOV_phase./time_phase;;     %gradient (phase): T/m

flag_tdr_loop=1;
flag_tdr_loop_full=0;

if(~flag_tdr_loop)
    %get the sampling time k-space coordinate.
    G_phase=repmat(grid_phase,[1 1 n_phase n_freq]);
    G_freq=repmat(grid_freq,[1 1 n_phase n_freq]);
    D_phase=repmat(([1:n_phase]-floor(n_phase./2)-1)',[1 n_phase n_freq n_freq]);
    D_phase=permute(D_phase,[2 3 1 4]);

    D_freq=repmat(([1:n_freq]-floor(n_freq./2)-1)',[1 n_phase n_freq n_phase]);
    D_freq=permute(D_freq,[2 3 4 1]);

    K_phase=exp(sqrt(-1).*(-1).*gamma.*grad_delta_phase.*D_phase.*time_phase.*FOV_phase./n_phase.*G_phase);
    K_freq=exp(sqrt(-1).*(-1).*gamma.*grad_max_freq.*delta_time_freq.*D_freq.*FOV_freq./n_freq.*G_freq);
elseif(flag_tdr_loop_full)
    %get the sampling time k-space coordinate.
    for y_idx=1:n_phase
        fprintf('TDR prep: [%03d|%03d]...\r',y_idx,n_phase);
        for x_idx=1:n_freq
            K_phase(y_idx,x_idx,:,:)=exp(sqrt(-1).*(-1).*gamma.*grad_delta_phase.*(y_idx-floor(n_phase./2)-1).*time_phase.*FOV_phase./n_phase.*grid_phase);
            K_freq(y_idx,x_idx,:,:)=exp(sqrt(-1).*(-1).*gamma.*grad_max_freq.*delta_time_freq.*(x_idx-floor(n_freq./2)-1).*FOV_freq./n_freq.*grid_freq);
        end;
    end;
    fprintf('\n')
end;


while(~convergence)
    if(flag_display)
        fprintf('PMRI recon. CG iteration=[%d]...',iteration_idx);
    end;

    dd=abs(r(:,:,iteration_idx-1)).^2;
    delta(iteration_idx)=sum(dd(:));


    if(sum(dd(:))<epsilon)
        convergence=1;
    else

        if(iteration_idx==2)

            p(:,:,iteration_idx)=r(:,:,1);
        else
            ww=sum(sum(abs(r(:,:,iteration_idx-1)).^2))/sum(sum(abs(r(:,:,iteration_idx-2)).^2));


            p(:,:,iteration_idx)=r(:,:,iteration_idx-1)+ww.*p(:,:,iteration_idx-1);
        end;

        %intensity correction here
        ss=p(:,:,iteration_idx).*I;

        for i=1:size(Y,3)
            %%%%%%%%%%%%%%%%%%%%%%%%%%%
            %%%         E          %%%%
            %%%%%%%%%%%%%%%%%%%%%%%%%%%

            % S (sensitivity)
            temp(:,:,i)=ss.*S(:,:,i);

            % FT2
            %%%%%temp(:,:,i)=fftshift(ifft2(fftshift(temp(:,:,i))));
            %temp0(:,:,i)=fftshift(fft2(fftshift(temp(:,:,i))));

            x=temp(:,:,i);
            %implemeting FT part by time-domin reconstruction (TDR)
            if((~flag_tdr_loop)|(flag_tdr_loop_full))
                X=repmat(x,[1 1 n_phase n_freq]);
                Temp=squeeze(sum(sum(K_phase.*K_freq.*X,1),2));
            else
                X=repmat(x,[1 1 n_freq]);
                %get the sampling time k-space coordinate.
                for y_idx=1:n_phase
                    fprintf('#');
                    k_phase=exp(sqrt(-1).*(-1).*gamma.*grad_delta_phase.*(y_idx-floor(n_phase./2)-1).*time_phase.*FOV_phase./n_phase.*grid_phase);
                    K_phase=repmat(k_phase,[1 1 n_freq]);

                    G_freq=repmat(grid_freq,[1 1 n_freq]);

                    D_freq=repmat(([1:n_freq]-floor(n_freq./2)-1)',[1 n_phase n_freq]);
                    D_freq=permute(D_freq,[2 3 1]);

                    K_freq=exp(sqrt(-1).*(-1).*gamma.*grad_max_freq.*delta_time_freq.*D_freq.*FOV_freq./n_freq.*G_freq);
                    Temp(y_idx,:)=squeeze(sum(sum(X.*K_freq.*K_phase,1),2));
                end;
            end;

            %             for y_idx=1:n_phase
            %                 for x_idx=1:n_freq
            %                     k_phase=exp(sqrt(-1).*(-1).*gamma.*grad_delta_phase.*(y_idx-floor(n_phase./2)-1).*time_phase.*FOV_phase./n_phase.*grid_phase);
            %                     k_freq=exp(sqrt(-1).*(-1).*gamma.*grad_max_freq.*delta_time_freq.*(x_idx-floor(n_freq./2)-1).*FOV_freq./n_freq.*grid_freq);
            %                     k_total=k_freq.*k_phase;
            %                     tmp=k_total.*x;
            %                     Temp(y_idx,x_idx)=sum(tmp(:));
            %                 end;
            %             end;

            if(flag_regrid_kb)  %performing roll-off
                x_in=[xgrid_freq(:),xgrid_phase(:)];
                y_in=Temp(:);
                x_out=[grid_freq(:),grid_phase(:)];

                if(isempty(regrid_kernel)|isempty(regrid_kernel_inv))
                    [Temp, regrid_kernel,regrid_kernel_inv]=etc_regridn(x_in,y_in,x_out,'flag_inv',1);
                    Temp=reshape(Temp,[n_phase,n_freq]);
                else
                    [Temp, regrid_kernel,regrid_kernel_inv]=etc_regridn(x_in,y_in,x_out,'kernel',regrid_kernel,'kernel_inv',regrid_kernel_inv,'flag_inv',1);
                    Temp=reshape(Temp,[n_phase,n_freq]);
                end;
            end;
            temp(:,:,i)=Temp;

            %K-space acceleration
            idx=find(K);

            buffer0=zeros(size(temp(:,:,i)));

            buffer1=zeros(size(temp(:,:,i)));
            buffer0=temp(:,:,i);
            buffer1(idx)=buffer0(idx);

            temp(:,:,i)=buffer1;

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %%%         E'          %%%%
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%

            %Density correction here

            % FT1
            %temp(:,:,i)=fftshift(fft2(fftshift(temp(:,:,i))));
            Temp=fftshift(ifft2(fftshift(temp(:,:,i))));

            if(flag_regrid_direct)
                idx=sub2ind([n_phase,n_freq],ceil(grid_phase(:))+n_phase/2+1,ceil(grid_freq(:))+n_freq/2+1);
                recon=reshape(Temp(idx),[n_phase,n_freq]);
            elseif(flag_regrid_kb)
                x_in=[xgrid_freq(:),xgrid_phase(:)];
                y_in=Temp(:);
                x_out=[grid_freq(:),grid_phase(:)];

                if(isempty(regrid_kernel)|isempty(regrid_kernel_inv))
                    [recon, regrid_kernel,regrid_kernel_inv]=etc_regridn(x_in,y_in,x_out,'flag_inv',0);
                    recon=reshape(recon,[n_phase,n_freq]);
                else
                    [recon, regrid_kernel,regrid_kernel_inv]=etc_regridn(x_in,y_in,x_out,'kernel',regrid_kernel,'kernel_inv',regrid_kernel_inv,'flag_inv',0);
                    recon=reshape(recon,[n_phase,n_freq]);
                end;
            end;
            temp(:,:,i)=recon;

            % S' (complex-conjugated sensitivity)
            temp(:,:,i)=temp(:,:,i).*conj(S(:,:,i));
        end;

        %intensity correction here
        xx=sum(temp,3).*I;

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        %%% CG starts
        q=xx;
        w=sum(sum(abs(r(:,:,iteration_idx-1)).^2))/sum(sum(conj(p(:,:,iteration_idx)).*q));

        b(:,:,iteration_idx)=b(:,:,iteration_idx-1)+p(:,:,iteration_idx).*w;


        r(:,:,iteration_idx)=r(:,:,iteration_idx-1)-q.*w;



        %%% CG ends

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        if(flag_debug)
            subplot(131);
            imagesc(abs(b(:,:,iteration_idx).*I)); colormap(gray); axis off image; colorbar;

            subplot(132);
            imagesc(abs(r(:,:,iteration_idx))); colormap(gray); axis off image; colorbar;

            subplot(133);
            imagesc(abs(p(:,:,iteration_idx))); colormap(gray); axis off image; colorbar;

            keyboard;

        end;
        iteration_idx=iteration_idx+1;

        if(iteration_idx > iteration_max)
            convergence=1;
        end;
    end;
    fprintf('\r');
end;

if(flag_display)
    fprintf('\n');
end;



%finalize output



if(size(b,3)>1)
    b(:,:,1)=[];

    delta(1)=[];
end;


%intensity correction for all;

for i=1:size(b,3)

    b(:,:,i)=b(:,:,i).*I;

end;

recon=b(:,:,end);