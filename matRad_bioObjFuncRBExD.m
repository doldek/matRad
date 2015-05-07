function [f, g] = matRad_bioObjFuncRBExD(w,dij,cst)
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% matRad optimization function based on the biological effecitve dose
% 
% call
%   [f, g] = matRad_bioObjFunc(w,dij,cst)
%
% input
%   w:   weight vector
%   dij: matRad dij struct
%   cst: cst file
%
% output
%   f: objective function value
%   g: gradient vector
%
% References
%   http://iopscience.iop.org/0031-9155/51/8/001
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Copyright 2015, Mark Bangert, on behalf of the matRad development team
%
% m.bangert@dkfz.de
%
% This file is part of matRad.
%
% matrad is free software: you can redistribute it and/or modify it under 
% the terms of the GNU General Public License as published by the Free 
% Software Foundation, either version 3 of the License, or (at your option)
% any later version.
%
% matRad is distributed in the hope that it will be useful, but WITHOUT ANY
% WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
% FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
% details.
%
% You should have received a copy of the GNU General Public License in the
% file license.txt along with matRad. If not, see
% <http://www.gnu.org/licenses/>.
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% Numbers of voxels
numVoxels = size(dij.physicalDose,1);

% calculate biological effect
linTerm  = dij.mAlphaDose*w;
quadTerm = dij.mSqrtBetaDose*w;
e = linTerm + quadTerm.^2;

% calculate RBX x dose
ScaledEffect = (e./dij.bx)+(dij.gamma.^2);
[idx,~] = find(~isnan(ScaledEffect));
% sqrt(ScaledEffect) takes 40% of the time
%ScaledEffect=sqrt(ScaledEffect);
ScaledEffect(idx)=sqrt(ScaledEffect(idx));
RBExD = ScaledEffect-dij.gamma;

% Initializes f
f = 0;

% Initializes delta
delta_underdose = zeros(numVoxels,1);
delta_overdose  = zeros(numVoxels,1);
delta_deviation = zeros(numVoxels,1);
delta_mean      = zeros(numVoxels,1);
delta_EUD       = zeros(numVoxels,1);

% Compute optimization function for every VOI.
for  i = 1:size(cst,1)
    
    % Only take OAR or target VOI.
    if isequal(cst{i,3},'OAR') || isequal(cst{i,3},'TARGET')
        
        % get rbe x dose vector in current VOI
        RBExD_i = RBExD(cst{i,4});
         
        % loop over the number of constraints for the current VOI
        for j = 1:size(cst{i,6},2)
            
            % get Penalty
            rho = cst{i,6}(j).parameter(1);
            
            if isequal(cst{i,6}(j).type, 'square underdosing')
  
                % underdose : biologic effecitve dose minus reference  biologic effecitve dose
                underdose = RBExD_i - cst{i,6}(j).parameter(2);

                % apply positive operator
                underdose(underdose>0) = 0;
                
                % calculate objective function
                f = f + (rho/size(cst{i,4},1))*(underdose'*underdose);
                
                % calculate delta
                delta_underdose(cst{i,4}) = delta_underdose(cst{i,4}) + (rho/size(cst{i,4},1))*underdose;
                
            elseif isequal(cst{i,6}(j).type, 'square overdosing')
                
                % overdose : biologic effecitve dose minus reference  biologic effecitve dose
                overdose = RBExD_i - cst{i,6}(j).parameter(2);
                
                % apply positive operator
                overdose(overdose<0) = 0;
                
                % calculate objective function
                f = f + (rho/size(cst{i,4},1))*(overdose'*overdose);
                
                %calculate delta
                delta_overdose(cst{i,4}) = delta_overdose(cst{i,4}) + (rho/size(cst{i,4},1))*overdose;
                
            elseif isequal(cst{i,6}(j).type, 'square deviation')
                
                % deviation : Dose minus prefered dose
                deviation = RBExD_i - cst{i,6}(j).parameter(2);
                
                % claculate objective function
                f = f + (rho/size(cst{i,4},1))*(deviation'*deviation);
                
                % calculate delta
                delta_deviation(cst{i,4}) = delta_deviation(cst{i,4}) + (rho/size(cst{i,4},1))*deviation;
               
            elseif isequal(cst{i,6}(j).type, 'mean')              
                
                % calculate objective function
                f = f + (rho/size(cst{i,4},1))*sum(RBExD_i);
                
                % calculate delta
                delta_mean(cst{i,4}) = delta_mean(cst{i,4}) + ...
                    (rho/size(cst{i,4},1))*ones(size(cst{i,4},1),1);
                
            elseif isequal(cst{i,6}(j).type, 'EUD') 
                
                % get exponent for EUD
                exponent = cst{i,6}(j).exponent;
                
                % calculate objective function and delta
                if sum(e_i.^exponent)>0
                    
                    f = f + rho*nthroot((1/size(cst{i,4},1))*sum(RBExD_i.^exponent),exponent);
                    
                    delta_EUD(cst{i,4}) = delta_EUD(cst{i,4}) + ...
                        rho*nthroot(1/size(cst{i,4},1),exponent) * sum(RBExD_i.^exponent)^((1-exponent)/exponent) * (RBExD_i.^(exponent-1));                    
                end    
                    
            else
                
                error('undefined objective in cst struct');
                
            end

        end
        
    end
end

% gradient calculation
if nargout > 1
    
    delta = delta_underdose + delta_overdose + delta_deviation;        
    delta = delta./(2*dij.bx.*ScaledEffect);
    vBias= (delta' * dij.mAlphaDose)';
    mPsi = (2*(delta.*quadTerm)'*dij.mSqrtBetaDose)';
    g = 2*(vBias+mPsi); 
    
    if sum(delta_mean(:))>0 || sum(delta_EUD(:))>0
        delta = delta_mean + delta_EUD;        
        delta = delta./(2*dij.bx.*ScaledEffect);
        vBias= (delta' * dij.mAlphaDose)';
        mPsi = (2*(delta.*quadTerm)'*dij.mSqrtBetaDose)';
        g = g + (vBias+mPsi); 
    end
    
end
