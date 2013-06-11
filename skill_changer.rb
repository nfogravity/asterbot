require 'open-uri'
require 'json'
require 'pry'

def replace_skill(json, n, new_text)
  monster = json[n.to_s]
  skill_text = monster["skill_text"]
  skill_text = skill_text.gsub(/Cool Down.*minimum/, new_text)
  monster["skill_text"] = skill_text
  json[n.to_s] = monster
  json
end

def write_dex(dex)
  f = File.open("modded_monsters.json", "w")
  f.write(dex.to_json)
  f.close
end

def try_skill(n)
  target_url = "http://www.puzzledragonx.com/en/monster.asp?n=#{n}"
  doc = open(target_url).read
  skill_text = doc.to_s.match(/\<td class="value-end">(.*)\<\/td\>\<\/tr\>\<tr\>\<td class="title"\>Cool Down:/)
  skill_text[1]
end

def exec(dex, bad_ids)
  bad_ids.each do |id|
    skill_text = try_skill(id)
    p "#{id}: #{skill_text}"
    dex = replace_skill(dex, id, skill_text) 
  end
  dex
end

bad_ids = [398,
399,
400,
401,
402,
403,
404,
405,
406,
407,
408,
409,
410,
411,
412,
415,
416,
418,
419,
421,
422,
424,
425,
427,
428,
441,
442,
443,
444,
446,
447,
448,
449,
450,
451,
452,
453,
454,
455,
456,
457,
458,
459,
460,
461,
462,
463,
464,
465,
466,
467,
468,
486,
487,
488,
489,
490,
491,
492,
493,
494,
495,
496,
497,
498,
499,
500,
501,
503,
505,
507,
509,
511,
520,
521,
522,
526,
527,
528,
529,
530,
531,
532,
533,
534,
535,
536,
537,
538,
539,
540,
541,
543,
544,
545,
546,
547,
548,
549,
550,
551,
552,
553,
554,
555,
556,
557,
558,
559,
560,
561,
562,
563,
564,
565,
566,
567,
568,
569,
570,
571,
572,
573,
574,
575,
576,
591,
592,
594,
595,
620,
621,
622,
623,
624,
625,
626,
627,
630,
631,
632,
633,
634,
635,
636,
637,
646,
647,
650,
651,
682,
683]

dex = JSON.parse(File.read("db/scraped_monsters.json"))
binding.pry
