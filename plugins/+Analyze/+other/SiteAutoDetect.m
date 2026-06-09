classdef SiteAutoDetect<interfaces.DialogProcessor&interfaces.SEProcessor
% Automatically detects clathrin-coated pit sites from SMLM localizations
% and adds them to the Site Explorer.
    methods
        function obj=SiteAutoDetect(varargin)
            obj@interfaces.DialogProcessor(varargin{:});
        end

        function out=run(obj,p)
            % Main Run button: run detection and add sites to SE
            params = obj.getParams();
            if isempty(params), out=[]; return; end
            obj.doDetect(params, false);
            out=[];
        end

        function initGui(obj)
            obj.guihandles.preview_button.Callback = @(~,~) obj.runPreview();
            obj.guihandles.detect_button.Callback  = @(~,~) obj.runDetect();
        end

        function runPreview(obj)
            params = obj.getParams();
            if isempty(params), return; end
            obj.doDetect(params, true);
        end

        function runDetect(obj)
            params = obj.getParams();
            if isempty(params), return; end
            obj.doDetect(params, false);
        end

        function pard=guidef(obj)
            pard=guidef_SiteAutoDetect(obj);
        end
    end

    methods(Access=private)
        function params = getParams(obj)
            params = [];
            try
                params.threshold    = str2double(obj.guihandles.threshold_edit.String);
                params.min_dist_nm  = str2double(obj.guihandles.min_dist_edit.String);
                params.blur_sigma   = str2double(obj.guihandles.blur_sigma_edit.String);
                params.clear_sites  = obj.guihandles.clear_sites.Value;
            catch
                warndlg('Could not read GUI parameters.'); return;
            end
            if any(isnan([params.threshold params.min_dist_nm params.blur_sigma]))
                warndlg('Invalid parameter values.'); params=[]; return;
            end
        end

        function doDetect(obj, params, preview_only)
            threshold   = params.threshold;
            min_dist_nm = params.min_dist_nm;
            blur_sigma  = params.blur_sigma;
            pixel_nm    = 10;

            % Get all localizations
            try
                locs = obj.locData.getloc({'xnm','ynm'}, 'removeFilter', 'filenumber');
            catch
                locs = obj.locData.getloc({'xnm','ynm'});
            end
            xnm = double(locs.xnm(:));
            ynm = double(locs.ynm(:));
            if isempty(xnm)
                warndlg('No localizations loaded.'); return;
            end

            % Build density map
            x_min = min(xnm);  y_min = min(ynm);
            W = ceil((max(xnm) - x_min) / pixel_nm) + 1;
            H = ceil((max(ynm) - y_min) / pixel_nm) + 1;
            xi = min(W, max(1, round((xnm - x_min) / pixel_nm) + 1));
            yi = min(H, max(1, round((ynm - y_min) / pixel_nm) + 1));
            img = accumarray([yi, xi], 1, [H W]);

            % Blur
            sigma_px = blur_sigma / pixel_nm;
            if exist('imgaussfilt','file') || exist('imgaussfilt','builtin')
                img_blur = imgaussfilt(double(img), sigma_px);
            else
                h = fspecial('gaussian', ceil(sigma_px*6+1)*2+1, sigma_px);
                img_blur = imfilter(double(img), h, 'replicate');
            end
            img_norm = img_blur / (max(img_blur(:)) + eps);

            % Find local maxima
            if exist('imregionalmax','file') || exist('imregionalmax','builtin')
                bw = imregionalmax(img_norm) & (img_norm > threshold);
            else
                se_dil = strel('disk', max(1, round(sigma_px)));
                bw = (imdilate(img_norm, se_dil) == img_norm) & (img_norm > threshold);
            end
            [rows, cols] = find(bw);
            if isempty(rows)
                msgbox('No sites detected. Try lowering the threshold.'); return;
            end

            % Convert to nm
            x_peaks = (cols - 1) * pixel_nm + x_min;
            y_peaks = (rows - 1) * pixel_nm + y_min;

            % Sort by descending intensity
            intensities = img_norm(sub2ind(size(img_norm), rows, cols));
            [~, order]  = sort(intensities, 'descend');
            x_peaks = x_peaks(order);
            y_peaks = y_peaks(order);

            % Enforce minimum distance (greedy; fast path via knnsearch for large N)
            N = length(x_peaks);
            kept = true(N, 1);
            if N > 1000 && (exist('knnsearch','file') || exist('knnsearch','builtin'))
                coords = [x_peaks, y_peaks];
                for k = 1:N
                    if ~kept(k), continue; end
                    idx = knnsearch(coords, coords(k,:), 'K', min(N,200));
                    idx = idx(idx > k);
                    d   = sqrt(sum((coords(idx,:) - coords(k,:)).^2, 2));
                    bad = idx(d < min_dist_nm);
                    kept(bad) = false;
                end
            else
                for k = 1:N
                    if ~kept(k), continue; end
                    dists = sqrt((x_peaks - x_peaks(k)).^2 + (y_peaks - y_peaks(k)).^2);
                    dists(k) = Inf;
                    rm = find(kept & dists < min_dist_nm);
                    rm = rm(rm > k);
                    kept(rm) = false;
                end
            end
            x_peaks = x_peaks(kept);
            y_peaks = y_peaks(kept);
            n_found = length(x_peaks);

            % Update count label
            try
                obj.guihandles.nsites_label.String = sprintf('N sites found: %d', n_found);
            catch
            end

            % Preview
            if preview_only
                cols_k = round((x_peaks - x_min) / pixel_nm) + 1;
                rows_k = round((y_peaks - y_min) / pixel_nm) + 1;
                figure('Name','SiteAutoDetect Preview','Color','k');
                imagesc(img_norm); colormap hot; axis equal tight; colorbar;
                hold on;
                plot(cols_k, rows_k, 'co', 'MarkerSize', 12, 'LineWidth', 2);
                title(sprintf('threshold=%.2f  |  %d sites detected', threshold, n_found), ...
                    'Color','w');
                fprintf('[SiteAutoDetect] Preview: %d sites at threshold=%.2f\n', n_found, threshold);
                return;
            end

            % Add to SE
            se = obj.SE;

            % Optionally clear existing sites
            if params.clear_sites && se.numberOfSites > 0
                ids = [se.sites(:).ID];
                for k = 1:length(ids)
                    try se.removeSite(ids(k)); catch, end
                end
            end

            % Ensure at least one file is registered in SE
            if isempty(se.files) || se.numberOfFiles == 0
                warndlg('No files registered in Site Explorer. Load data first.'); return;
            end
            filenumber = se.files(1).ID;

            % Create one parent cell for all detected sites
            newcell = interfaces.SEsites;
            newcell.pos = [mean(x_peaks), mean(y_peaks), 0];
            newcell.ID  = 0;
            newcell.info.filenumber = filenumber;
            cellID = se.addCell(newcell);

            % Add sites
            for k = 1:n_found
                site = interfaces.SEsites;
                site.pos  = [x_peaks(k), y_peaks(k), 0];
                site.ID   = 0;
                site.name = sprintf('CCP_%04d', k);
                site.info.filenumber = filenumber;
                site.info.cell       = cellID;
                se.addSite(site);
            end

            % Refresh SE display
            try
                se.processors.preview.updateCelllist;
                se.processors.preview.updateSitelist;
            catch
            end

            fprintf('[SiteAutoDetect] Added %d sites to SE (file %d)\n', n_found, filenumber);
        end
    end
end


function pard = guidef_SiteAutoDetect(obj)

pard.t_thresh.object = struct('String','Threshold (0–1)','Style','text');
pard.t_thresh.position = [1,1];
pard.t_thresh.Width = 1.2;

pard.threshold_edit.object = struct('String','0.02','Style','edit');
pard.threshold_edit.position = [1,2.3];
pard.threshold_edit.Width = 0.6;

pard.t_dist.object = struct('String','Min site distance (nm)','Style','text');
pard.t_dist.position = [2,1];
pard.t_dist.Width = 1.2;

pard.min_dist_edit.object = struct('String','150','Style','edit');
pard.min_dist_edit.position = [2,2.3];
pard.min_dist_edit.Width = 0.6;

pard.t_blur.object = struct('String','Blur sigma (nm)','Style','text');
pard.t_blur.position = [3,1];
pard.t_blur.Width = 1.2;

pard.blur_sigma_edit.object = struct('String','40','Style','edit');
pard.blur_sigma_edit.position = [3,2.3];
pard.blur_sigma_edit.Width = 0.6;

pard.clear_sites.object = struct('String','Clear existing sites first','Style','checkbox','Value',0);
pard.clear_sites.position = [4,1];
pard.clear_sites.Width = 2;

pard.preview_button.object = struct('String','Preview','Style','pushbutton');
pard.preview_button.position = [5,1];
pard.preview_button.Width = 1;

pard.detect_button.object = struct('String','Detect Sites','Style','pushbutton');
pard.detect_button.position = [5,2];
pard.detect_button.Width = 1;

pard.nsites_label.object = struct('String','N sites found: ---','Style','text');
pard.nsites_label.position = [6,1];
pard.nsites_label.Width = 2;

pard.plugininfo.name        = 'Auto-detect CCP Sites';
pard.plugininfo.description = 'Detects clathrin-coated pits from SMLM localizations via density map + local maxima.';
pard.plugininfo.type        = 'ProcessorPlugin';
end
