#!/usr/bin/env ruby
#-----------------------------------------------------------------------------------------------
# stacks2baits
STACKS2BAITSVER = "0.3"
# Michael G. Campana, 2017
# Smithsonian Conservation Biology Institute
#-----------------------------------------------------------------------------------------------

class Popvar # Population-specific SNP data object
	attr_accessor :pop, :alleles, :no_ind, :pfreq, :hetobs, :line 
	def initialize(pop, alleles, no_ind, pfreq, hetobs, line)
		@pop = pop # Population
		@alleles = alleles # Array of alleles
		@no_ind = no_ind # Sample size,
		@pfreq = pfreq # Major frequency
		@hetobs = hetobs # Observed heterozygosity
		@line = line # Original SNP descriptor line
	end
	def monomorphic? # Determine if SNP is monomorphic within population
		if (@pfreq == 1 or @pfreq == 0)
			return true
		else
			return false
		end
	end
	def in_hwe? # Return whether variant is in HWE for a population
		qfreq = 1 - @pfreq # Calculate minor allele frequency
		p2exp = @pfreq ** 2 * @no_ind  # Calculate expected major allele homozygotes
		q2exp = qfreq ** 2 * @no_ind # Calculate expected minor allele homozygotes
		pqexp = (2 * @pfreq * qfreq) * @no_ind # Calculate expected heterozygotes
		pqobs = (@hetobs * @no_ind).to_i
		p2obs = ((@pfreq - @hetobs/2) * @no_ind).to_i # Calculate observed major alleles in homozygotes
		q2obs = ((qfreq - @hetobs/2) * @no_ind).to_i # Calculate observed minor alleles in homozygotes
		hwe = ((p2obs - p2exp) ** 2)/p2exp + ((pqobs - pqexp) ** 2)/pqexp + ((q2obs - q2exp) ** 2)/q2exp # Calculate chi-square statistic
		case $options.alpha
		when 0.1
			alpha = 2.706
		when 0.05
			alpha = 3.841
		when 0.025
			alpha = 5.024
		when 0.01
			alpha = 6.635
		end
		if hwe < alpha # Compare to alpha 0.05
			return true
		else
			return false
		end
	end
end
#-----------------------------------------------------------------------------------------------
def write_stacks(header, snps, tag) # Method to write stacks output since repeating over and over
	for key in snps.keys
		for ssnp in snps[key]
			header += ssnp.line
		end
	end
	File.open($options.outdir + "/" + $options.outprefix + tag + ".tsv", 'w') do |write|
		write.puts header
	end
end
#-----------------------------------------------------------------------------------------------
def stacks2baits
	# Read stacks summary tsv file
	print "** Reading stacks tsv **\n"
	stacksvars = {} # Hash, keying by stacks Locus ID and SNP index
	stacksheader = "" # Stacks TSV header
	File.open($options.infile, 'r') do |stacks|
		while line = stacks.gets
			if line[0].chr != "#"
				split_line = line.split("\t")
				locus = split_line[1]+split_line[4]
				chromo = split_line[2]
				len = split_line[3].to_i # Length
				snp = split_line[4].to_i + 1 #Stacks uses 0-based counting
				pop = split_line[5] # Population
				alleles = [split_line[6], split_line[7]] # Get major, minor alleles
				alleles.delete("-") # Remove non-alleles, separate command to avoid assigning alleles as "-"
				no_ind = split_line[8].to_i # No. of individuals
				pfreq = split_line[9].to_f # Major allele frequency
				hetobs = split_line[10].to_f # Observed heterozygosity
				if stacksvars.include?(locus)
					stacksvars[locus].popvar_data.push(Popvar.new(pop, alleles, no_ind, pfreq, hetobs, line))
				else
					stacksvars[locus]=Chromo_SNP.new(chromo, snp, [Popvar.new(pop, alleles, no_ind, pfreq, hetobs, line)])
					scaled = (len/$options.distance).floor
					$options.scalehash[chromo] = scaled
				end
			else
				stacksheader += line
			end
		end
	end
	# Sort SNPs and convert to usable form for selectsnps algorithm
	print "** Sorting SNPs **\n"
	between_pops = {} # Hash to hold SNPs that are only variable between populations (also all SNPs if not sorting)
	within_pops = {} # Hash to hold SNPs that are variable within populations (overrides between_pops)
	in_hwe = {} # Hash to hold SNPs that are in HWE within populations
	out_hwe = {} # Hash to hold SNPs that are not in HWE within populations
	for key in stacksvars.keys
		snp = stacksvars[key]
		if snp.within_pops? and $options.sort
			if within_pops.include?(snp.chromo)
				within_pops[snp.chromo].push(snp)
			else
				within_pops[snp.chromo]=[snp]
			end
			if $options.hwe
				hwe = true
				for pop in snp.popvar_data # If any population has the SNP out-of-HWE, exclude it
					if !pop.in_hwe?
						hwe = false
						break
					end
				end
				if hwe
					if in_hwe.include?(snp.chromo)
						in_hwe[snp.chromo].push(snp)
					else
						in_hwe[snp.chromo]=[snp]
					end
				else
					if out_hwe.include?(snp.chromo)
						out_hwe[snp.chromo].push(snp)
					else
						out_hwe[snp.chromo]=[snp]
					end
				end
			end
		else
			if between_pops.include?(snp.chromo)
				between_pops[snp.chromo].push(snp)
			else
				between_pops[snp.chromo]=[snp]
			end
		end
	end
	# Select SNPs -- Note that there is no cross-referencing between types
	print "** Selecting SNPs **\n"
	$options.logtext += "BetweenPopsVariants\n" if $options.log
	selected_between = selectsnps(between_pops)
	write_stacks(stacksheader, selected_between, "-betweenpops")
	if $options.sort and $options.hwe
		$options.logtext += "InHWEVariants\n" if $options.log
		selected_inhwe = selectsnps(in_hwe)
		$options.logtext += "OutHWEVariants\n" if $options.log
		selected_outhwe = selectsnps(out_hwe)
		write_stacks(stacksheader, selected_inhwe, "-inhwe")
		write_stacks(stacksheader, selected_outhwe, "-outhwe")	
	elsif $options.sort
		$options.logtext += "WithinPopsVariants\n" if $options.log
		selected_within = selectsnps(within_pops)
		write_stacks(stacksheader, selected_within, "-withinpops")
	end
	# Output baits unless -p
	if !$options.no_baits
		print "** Reading reference sequence **\n"
		refseq = read_fasta($options.refseq)
		print "** Generating and filtering baits **\n"
		$options.logtext += "BetweenPopsVariantBaits\n" if $options.log
		bbaits = snp_to_baits(selected_between, refseq)
		write_stacks(stacksheader, bbaits[5], "-betweenpops-filtered")
		write_baits(bbaits[0], bbaits[1], bbaits[2], bbaits[3], bbaits[4], $options.infile+"-betweenpops")
		if $options.sort and $options.hwe
			$options.logtext += "InHWEVariantBaits\n" if $options.log
			ihbaits = snp_to_baits(selected_inhwe, refseq)
			$options.logtext += "OutHWEVariantBaits\n" if $options.log
			ohbaits = snp_to_baits(selected_outhwe,refseq)
			write_stacks(stacksheader, ihbaits[5], "-inhwe-filtered")
			write_stacks(stacksheader, ohbaits[5], "-outhwe-filtered")
			write_baits(ihbaits[0], ihbaits[1], ihbaits[2], ihbaits[3], ihbaits[4], $options.infile+"-inhwe")
			write_baits(ohbaits[0], ohbaits[1], ohbaits[2], ohbaits[3], ohbaits[4], $options.infile+"-outhwe")
		elsif $options.sort
			wbaits = snp_to_baits(selected_within_pops, refseq)
			$options.logtext += "WithinPopsVariantBaits\n" if $options.log
			write_stacks(stacksheader, wbaits[5], "-withinpops-filtered")
			write_baits(wbaits[0], wbaits[1], wbaits[2], wbaits[3], wbaits[4], $options.infile+"-withinpops")
		end
	end
end