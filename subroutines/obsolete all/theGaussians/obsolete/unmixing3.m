% umixing.m
% This function umixes given components obtained by RCA
% input: organList (stacked images of components)
%        cube (stacked raw images)

%% temporal initialization
clc;
close all;
clear x;
x = cube;
N = size(x);
M = size(organList);
mask = zeros(M); % stores the masks of the background and organs
finalSpectra = zeros(N(3),M(3)); % will store the pure background and organs spectra

%% section that converts x to y by stacking images as columns
y = zeros(N(1)*N(2),N(3));
for i = 1:N(3) 
    temp = x(:,:,i); 
    y(:,i) = temp(:); 
end
y = y';

%% finds the true reconstruction
[compositeImage, thresholdedImage] = FindCoeff(Atrue,y,N,1);
close all;

%% segment organs, obtains variable 'mask'
% 1) segments the organs (so far only thresholds them, can be improved)
% 2) find the convex hulls and posibly dilates them
% 3) calculate overlaping and non-overlaping regions and gives the percentage of overlap for each organ
% 4) calulate the spectra based on everything
%     4.1) find the "pure" spectra using non overlap region
%     4.2) finds the "mixed" spectra usign overlap region

%% 1. Components are segmented and variable 'mask' is obtained (so far program only thresholds them; can be improved)
for i = 1:M(3)
    image = organList(:,:,i);
    % different mask for background (i=1) and the rest of the organs
    if i == 1
        mask(:,:,i) = image > 0.10 * ( max(image(:)) - min(image(:)) ) + min(image(:));
    else
        mask(:,:,i) = image > 0.5 * ( max(image(:)) - min(image(:)) ) + min(image(:));
    end
    Puti(mask(:,:,i),num2str(i),i,[0,1]);
end

%% 2. Convex hulls of masks are obtained
for i = 1:M(3)
    mask(:,:,i) = FindConvexRegion(mask(:,:,i));
    Puti(mask(:,:,i),num2str(i),i,[0,1]);
end

%% 3. Overall background spectrum is determined
% excludes organs region from background spectra calculation by dilating
% the Union of the organ masks that has been Dilated for finalSpectra certain size
% (here 3 pixels)

maskOfAllOrgans = DilateMask ( sum( mask(:,:,2:M(3)), 3), 3 );
mask(:,:,1) = (mask(:,:,1) - maskOfAllOrgans ) > 0;
% finds the background spectrum imediatelly
for j = 1:N(3)
    finalSpectra(j,1) = mean(mean(  x(:,:,j) .* mask(:,:,1)) );
end
pos(3);  plot(finalSpectra(:,1));  title('Background');

%% 4. Overlaps masks and true reconstructions
for i = 2:M(3)
    Puti(0.9 * compositeImage + 0.1 * BWToRGB(mask(:,:,i)),num2str(i),i,[0,1]);
end

%% 6. Main part: Calculates the finalSpectra 
% Idea: For every organ mask, two contoures are computed, one inside and one outside the mask. The outside contour goes 
% just enough to obtain spectra that is distincive enough.

% Implementation: 
% 1. Finds the inside and initial outside contours. 
% 2. For all the points on the outside contour computes the pure spectrum 
%    using the closest point at the inside contour.
% 3. If the spectrum is distinctive enough program FIXES the point, if not, moves 
%    the contour one pixel further away.
% 4. Finds the new contour
% 5. Repeats until the new contour is identical to old one

for i = 2:M(3)
    
    % 1. 
    % finds the two contours for organ 'i'
    outsideContour = FindOutsideContour( mask(:,:,i), 3);
    insideContour = FindInsideContour( mask(:,:,i), 3);
    
%    next 3 lines are preparation to use DSEARCH (matlab function for finding nearest point) 
%    X and Y are vector representation of insideContour
%    TRI is finalSpectra simplex of insideContour that is used by DSEARCH
%    XI and YI are vector representation of outsideContour

    [X,Y] = ConvertContourToVector( insideContour);
    TRI = delaunay(X,Y);
    [XI,YI] = ConvertContourToVector( outsideContour);
    
    % Puti(0.5 * compositeImage + 0.25 * BWToRGB(insideContour) + 0.25 * BWToRGB(maskEroded(:,:,i)),num2str(i),i,[0,1]);
    % Puti(insideContour(:,:,i),num2str(i),i,[0,1]);

    numberOfPoints = length(XI);
    % Variable 'checked' is finalSpectra map of pixels that are fixed.
    % Its purpose is to skip the calculations of those spectra.
    checked = zeros( M(1), M(2));
    
    % variable 'finalOrganSpectra' is going to store all the fixed spectra in columns
    finalOrganSpectra = zeros( N(3), numberOfPoints);
    
    % our criterion of stoping is going to be that all the points are fixed
    bool = numberOfPoints ~= sum(checked(:));
    if bool
        for j = 1 : numberOfPoints
            % j is the currentPoint
            if checked( XI(j), YI(j) ) == 0
                
                % 2. 
                % find the index ('K') of the closest point (X(K) and Y(K) are
                % coordinates)
                K = dsearch( X, Y, TRI, XI(j), YI(j));

                % find the spectrum of outside and inside point (insideSpectrum can be
                % precalculated in the future)
                [outsideSpectrum, pointsUsedOutside] = SpectrumAroundPoint( x, newOutsideContour, XI(j), YI(j), 5);
                [insideSpectrum, pointsUsedInside] = SpectrumAroundPoint( x, newOutsideContour, X(K), Y(K), 5);
                
                % finds the pure spectrum
                [spectrum, parameters] = ComputePureSpectrum( insideSpectrum, outsideSpectrum, 1);
                
                % presents the spectra
                inside = { insideContour, pointsUsedInside, insideSpectrum };
                outside = { outsideContour, pointsUsedOutside, outsideSpectrum};
                showSpectra( compositeImage, inside, outside, spectrum, parameters);
                
                % 3. 
                if SpectraDistinctiveEnough(spectrum)
                    %fix the point XI(j),YI(j)
                    outsideContour(XI(j),YI(j)) = 1;
                    checked( XI(j), YI(j) ) = 1;
                    finalOrganSpectra(:,j) = spectrum;
                else
                    % move the outisedContour pixel XI(j),YI(j) further away
                    outsideContour( XI(j), YI(j)) = 0;
                    outsideContour( MovePixelFurtherAway([ XI(j), YI(j)],[ X(K), Y(K)],[ M(1), M(2)])) = 1;
                    checked( XI(j), YI(j) ) = 0;
                end
            end
        end
        
        % 4.
        newOutsideContour = createNewContour( outsideContour);
        % 5.
        bool = numberOfPoints ~= sum(checked(:));
    end
    finalSpectra(:,i) = mean(finalOrganSpectra,2);    
    PresentContour(mask(:,:,i), outsideContour, insideContour)
end
pos(3);  finalSpectra = NormalizeSpectra(finalSpectra); plot(finalSpectra);  title('finalSpectra');


for i = 2:M(3)
    finalSpectra(:,i) = ComputePureSpectrum( finalSpectra(:,i), finalSpectra(:,1),1);
end
Pos(4); finalSpectra = NormalizeSpectra(finalSpectra); plot(finalSpectra); title('finalSpectra after shrinking');

%% 
[compositeImage, tImage] = FindCoeff(finalSpectra,y,N,1);