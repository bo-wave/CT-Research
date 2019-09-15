% 19/05/22 by ZXZ
%TV based iterative algorithm with patch prior
% set prior term as the penalty term instead of just setting as an initiate
tic
clear;
% close all;
%%
% lab computer
% load 'G:\CTcode\Data\trial2D'
% server2 path
load ..\Data\trial2D
load ..\Data\trial2D_prior_360
save_path = '..\Data\PICCS_miu200_lamda0.001_p4s3sp5_CGzero_init\' ;
% load 'E:\ZXZ\Data\trial2D_angle5'
% display parameter
displaywindow = [0 0.5] ;

% parameter define
thetaint = deg2rad(5) ;                                                                 % theta unit 
Maxtheta = deg2rad(360) ;
thetaRange = thetaint : thetaint : Maxtheta ;                                % radon scanning range
Ltheta = length ( thetaRange ) ; 

pic = trial2D ; 
% clear trial2D
% pic = phantom(512) ;
Size = [ 60 , 60 ] ;                                  % actual range

[ height , width ] = size ( pic ) ;              % store the size of picture
Resolution = max ( Size ) / height ;   % define the resolution of pic
Center_y = Size ( 1 ) / 2 ;  Center_x = Size ( 1 ) / 2 ;      % define the center 
Rpic = 0.5 * sqrt ( 2 ) * Size ( 1 ) ; 

tmax = round ( Rpic * 1.1 ) ;
t_int = 0.1 ;
t_range =  -tmax : t_int : tmax ;
Lt = length ( t_range ) ;

R = zeros ( Lt ,  Ltheta ) ;   % create space to store fan projection
%% compute system matrix

% SysMatrix = GenSysMatParal ( height , width , Size , Center_x , Center_y , thetaRange , t_range ) ;
load SysMatrix
picvector = Img2vec_Mat2Cpp2D( pic ) ;  % original image
clear pic
R = SysMatrix * double(picvector) ;        % generate projection with system matrix
% R = reshape( R , Lt , Ltheta ) ;
% figure,imshow(R,[])
% Norm = norm ( R ) ;
% Norm_pic = norm ( picvector ) ;
% % load A.mat
% % SysMatrix = A ; 
%% GPU-based projection 
% picvector = Img2vec_Mat2Cpp2D( pic ) ;
% R = ProjectionParallel_2D( picvector , height , width , Size ,thetaRange' , t_range' ) ;     % store parallel beam projection
% R2 = reshape( R2 , Lt , Ltheta ) ;
% figure,imshow(R2,[])

%% iterative
% S.Kaczmarz Method
Threshold = 1e-6 ;
innerTimes = 15 ;
MaxLim = 1 ; MinLim = 0 ;    % value limit
miu = 200 ;        % regularization parameter for TV
alpha = 0.5 ;    % panelty balance between the prior and the current 
lamda1 = 0.001 * miu ;           lamda2 = 0.001 * miu ;            % relaxtion factor for split bregman( 2*miu is recommended by the classical paper)
Display = zeros ( height * width , 1 ) ;          % store the reconstruction
LDisplay = numel ( Display ) ;

% Err = R - ProjectionParallel_2D( single(Display) , height , width , Size ,thetaRange' , t_range' ) ;
% Err = R - SysMatrix * Display ;
% Residual = zeros ( Times ) ;  Residual ( 1 ) = norm ( Err ) / ( Norm ) ;      % used as stop condition
figure  % hold residual graph
load ..\Data\Display_previous
% Display_previous = FBPparallel( single(R) , single(thetaRange') , single(t_range') , Size , height ,width ) ;

Display_previous = Vec2img_Cpp2Mat2D( Display_previous , height , width ) ;
imshow ( Display_previous , displaywindow ) ;                     % display results
drawnow;
            
gradientMatrix_x = gradient2Dmatrix_x(height,width);
gradientMatrix_y = gradient2Dmatrix_y(height,width);

% preparation for CG
divergence_matrix = divergenceMatrix2D(height,width);
b1_CG = miu * (SysMatrix') * R ; 
iter_CG = 500 ;
% img_init = zeros(LDisplay,1) ; 

% patch operation parameter
patchsize = [4 , 4] ; 
slidestep = [3 , 3] ;
sparsity = 5 ; 
% construct dictionary, because here image patches are directly used as
% atom, dictionary keeps still
HighQ_image = trial2D ;
% HighQ_image = trial2D_prior_360 ;
clear trial2D_prior_360
patchset_HighQ = ExtractPatch2D ( HighQ_image , patchsize , slidestep, 'NoRemoveDC' ) ;    % extract the patches from the high quality image as the atoms of the dictionary, which should be normalized later
Dictionary = col_normalization( patchset_HighQ ) ;    % Dictionary, of which each atom has been normalized 
 
% max outloop
outeriter = 20 ;
rmse = zeros( innerTimes , outeriter ) ;                                       % judgement parameter
PSNR = zeros( innerTimes , outeriter ) ;
for outerloop = 1 : outeriter
    disp(['outerloop : ' , num2str(outerloop),'/',num2str(outeriter)])
    %% patch operation
    Display = double ( Img2vec_Mat2Cpp2D( Display_previous ) ) ;      % set the result of last iterate as the initiate value of current iterate
    patchset_LowQ = ExtractPatch2D ( Display_previous , patchsize , slidestep, 'NoRemoveDC' ) ;    % extract the patches from the low quality image which need to be improved, store here to compute the DC later
       
    Xintm = ExtractPatch2D ( Display_previous, patchsize, slidestep, 'NoRemoveDC' ) ;    % Xintm is set of patches which extracted from the low quality image
    Alpha = omp( Dictionary , Xintm , Dictionary' * Dictionary , sparsity ) ;     % use OMP to fit Xintm
    Image2D = PatchSynthesis ( Dictionary * Alpha, patchset_LowQ, patchsize, slidestep, [height , width], 'NoAddDC' ) ;    % fuse all patches
    imshow ( Image2D , displaywindow ) ;                     % display results
    drawnow ;
    Display_prior = double ( Img2vec_Mat2Cpp2D( Image2D ) );
    
    % initial of inner SB iterative, all parameter should be initialized
    % based on zero input
    dx1 = zeros(LDisplay,1); dy1 = zeros(LDisplay,1); bx1 = zeros(LDisplay,1); by1 =zeros(LDisplay,1);   
    dx2 = gradientMatrix_x * (-Display_prior) ; dy2 = gradientMatrix_y * (-Display_prior) ; bx2 = zeros(LDisplay,1); by2 =zeros(LDisplay,1);   
    % initial of range limitation parameter
    % parameter initiation in the range limitation ( min < x < max)
    miu1 = zeros(LDisplay,1) ;
    miu2 = zeros(LDisplay,1) ;
    xig1 = 0.1 * 2^0;
    xig2 = 0.1 * 2^0;
    rate1 = 2 ; 
    rate2 = 2 ;
    
    local_e = 100 ;     % initial
    IterativeTime = 1  ;      % times to iterative
    
    Display = zeros(LDisplay,1) ;
    %% split bregman to solve tv-based problem
    while ( IterativeTime <= innerTimes && local_e > Threshold )            % end condition of loop
                 Display_previous = Display ;
                 % introduce the range limitation into the iterative
                 % framework
%                  Display_det1 = max( 0 , miu1 - xig1 * ( Display_previous - MinLim ) ) ;  Display_det1 = Display_det1 ./ ( Display_det1 + eps ) ;
%                  Display_det2 = max( 0 , miu2 - xig2 * ( -Display_previous + MaxLim ) ) ;  Display_det2 = Display_det2 ./ ( Display_det2 + eps ) ;
%                  Display_det1 = xig1 * sparse( 1:LDisplay, 1:LDisplay, Display_det1, LDisplay , LDisplay ) ;
%                  Display_det2 = xig2 * sparse( 1:LDisplay, 1:LDisplay, Display_det2, LDisplay , LDisplay ) ;
                 Display_det1 = 0 ; Display_det2 = 0 ;
                 
                 b_CG = b1_CG + lamda1 * ( gradientMatrix_x * ( dx1 - bx1 ) + gradientMatrix_y * ( dy1 - by1 ) ) ... 
                 + lamda2 * ( gradientMatrix_x * ( dx2 + gradientMatrix_x * Display_prior - bx2 ) + gradientMatrix_y * ( dy2 + gradientMatrix_y * Display_prior - by2 ) ) ...
                 + Display_det1 * ( xig1 * MinLim + miu1 ) + Display_det2 * ( xig2 * MaxLim - miu2 ) ;
                  
                 % here are two choices: 1. using the previous result; 2. using zero initialization
                 % To solve Ax = b , the paramter matrix A is already a
                 % semidefinite full-rank matrix, so there is no need to
                 % use norm equation
                 systemfunc = @(vec,tt) miu * (SysMatrix') * ( SysMatrix * vec ) + (lamda1 + lamda2) * divergence_matrix * vec ;
%                  [Display,flag,resNE,iter] = cgls(systemfunc, b_CG, 0, 1e-6, iter_CG, true, Display_previous) ;
                 [Display,flag,resNE,iter] = cg(systemfunc, b_CG, 1e-6, iter_CG, true, Display_previous,double(picvector)) ;
                 
%                  Display = cg4TV ( SysMatrix, divergence_matrix , Display_det1, Display_det2, b_CG , iter_CG , miu , lamda1 + lamda2 , Display_previous ) ;        
%                  Display = cgls4TV ( SysMatrix, divergence_matrix , b_CG , iter_CG , miu , lamda1 + lamda2 , Display_previous) ;        
                 miu1 = max(0 , miu1 - xig1 * (Display - MinLim)) ; miu2 = max( 0 , miu2 - xig2 * (-Display + MaxLim ) ) ;
                 xig1 = xig1 * rate1 ; xig2 = xig2 * rate2 ;
                 Display ( Display < MinLim ) = MinLim ;       Display ( Display > MaxLim ) = MaxLim ;   % non-negation constraint
                 
                 Substract_Display = Display - Display_prior ;
                 dx1 = soft_threshold( gradientMatrix_x * Display + bx1 , alpha/(lamda1+eps));         % split bregman update
                 dy1 = soft_threshold( gradientMatrix_y * Display + by1 , alpha/(lamda1+eps));
                 dx2 = soft_threshold( gradientMatrix_x * Substract_Display + bx2 , (1-alpha)/(lamda2+eps));         % split bregman update
                 dy2 = soft_threshold( gradientMatrix_y * Substract_Display + by2 , (1-alpha)/(lamda2+eps));
                 bx1 = bx1 - dx1 + gradientMatrix_x * Display ; 
                 by1 = by1 - dy1 + gradientMatrix_y * Display ; 
                 bx2 = bx2 - dx2 + gradientMatrix_x * Substract_Display ; 
                 by2 = by2 - dy2 + gradientMatrix_y * Substract_Display ; 
               
                 rmse ( IterativeTime ,outerloop) = RMSE ( Display , picvector) ;      % compute error
                 PSNR( IterativeTime ,outerloop) = psnr ( Display , double(picvector) , 1) ; 
                 local_e = LocalError( Display , Display_previous ) ;
                 % objective function ( which is different from the previous)
                 loss = alpha * (norm(gradientMatrix_x * Display,1) + norm(gradientMatrix_y * Display,1)) + ( 1 - alpha ) * (norm(gradientMatrix_x * Substract_Display,1) + norm(gradientMatrix_y * Substract_Display,1))...
                 + 0.5 * miu * norm(SysMatrix * Display - R ,2) ;     
                 disp ( ['IterativeTime: ', num2str(IterativeTime), ';   |    RMSE: ', num2str(rmse ( IterativeTime ,outerloop)), ';   |    psnr: ', num2str(PSNR ( IterativeTime , outerloop)), ';   |    local_e: ', num2str(local_e), ';   |    Loss: ', num2str(loss)]) ;
                 disp( ['SplitBregman_Constraint_X1: ',  num2str(norm(dx1-gradientMatrix_x * Display,2)), '  Constraint_Y1: ', num2str(norm(dy1-gradientMatrix_y * Display,2)), ...
                     '  Constraint_X2: ', num2str(norm(dx2-gradientMatrix_x * Substract_Display,2)), '  Constraint_Y2: ' , num2str(norm(dy2-gradientMatrix_y * Substract_Display,2))] )
    %     plot ( 2 : IterativeTime , rmse ( 2  : IterativeTime ) ) ;
    %     ylim ( [ 0 , ( 10 * rmse ( IterativeTime ) ) ] ) ;
    %     drawnow ;           

                IterativeTime = IterativeTime + 1 ;
    end

    Display = Vec2img_Cpp2Mat2D( Display , height , width ) ;
    imshow ( Display , displaywindow ) ;                     % display results
    drawnow;
    save_path_pic = strcat(save_path,num2str(outerloop)) ;
    save( save_path_pic, 'Display') ;
    Display_previous = Display ;
end
save_path_rmse = strcat(save_path , 'rmse') ;
save( save_path_rmse , 'rmse' );
save_path_psnr = strcat(save_path , 'PSNR') ;
save( save_path_psnr , 'PSNR' );
% figure , imshow ( Display_previous , displaywindow ) ;                     % display results

% figure, plot ( 1 : Times , MSE( 1  : Times ) ) ;                          % display error graph
% title ( ' error graph ' ) ;

% figure,plot( 1 : size ( pic , 1 ) , Display ( : , 129 ) , 1 : size ( pic , 1 ) , pic ( : , 129 ) ) ;    % display transversal
% title ( ' grey distrubition ' ) ;
% axis ( [ 0 256 0 1 ] ) ;


 toc