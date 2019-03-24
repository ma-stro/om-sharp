;============================================================================
; om7: visual programming language for computer-aided music composition
; Copyright (c) 2013-2017 J. Bresson et al., IRCAM.
; - based on OpenMusic (c) IRCAM 1997-2017 by G. Assayag, C. Agon, J. Bresson
;============================================================================
;
;   This program is free software. For information on usage 
;   and redistribution, see the "LICENSE" file in this distribution.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
;
;============================================================================
; File author: J. Bresson
;============================================================================


(in-package :om)

;;;====================================================
;;; DRAW METHODS FOR SCORE EDITOR / MINIVIEW
;;;====================================================

;;; MINIVIEW
(defmethod score-object-mini-view ((self voice) box x-pix y-u w h)
  
  (draw-staff x-pix y-u w h (fontsize box) (get-edit-param box :staff) :margin-l 1 :margin-r 1 :keys t)

  (loop for m in (inside self)
        for i from 1
        do (draw-score-element m (tempo self) box (frame box) :y-shift y-u :font-size (fontsize box) :position i)
        ))


;;; EDITOR
(defmethod draw-sequence ((object voice) editor view unit)

  ;;; NOTE: so far we don't build/update a bounding-box for the containers
  
  (let ((on-screen t))
    (loop for m in (inside object)
          for i from 1
          while on-screen
          do (let* ((begin (beat-to-time (symbolic-date m) (tempo object)))
                    (end (beat-to-time (+ (symbolic-date m) (symbolic-dur m)) (tempo object)))
                    (x1 (time-to-pixel view begin))
                    (x2 (time-to-pixel view end)))
               
               (if (> x1 (w view)) (setf on-screen nil)
                 ;;; else :
                 (when (> x2 0) 
                   
                   ;;; DRAW THIS MEASURE
                   (draw-score-element m (tempo object) (object editor) view :position i
                                       :font-size (editor-get-edit-param editor :font-size)
                                       :selection (selection editor))
                   )))
          ))
  )


;;;===============================================
;;; MEASURE
;;;===============================================

(defmethod draw-score-element ((object measure) tempo param-obj view 
                               &key font-size (y-shift 0) (level 0) position beam-info selection)

  (declare (ignore level beam-info))

  (let ((x-pix (time-to-pixel view (beat-to-time (symbolic-date object) tempo))))
    
    (unless (= position 1) 
      (draw-measure-bar x-pix y-shift font-size (get-edit-param param-obj :staff))
      (om-draw-string x-pix (- y-shift 1) (number-to-string position)
                      :font (om-def-font :font1 :size (/ font-size 3))))
                   
    (loop for element in (inside object) 
          for i from 0 do
          (draw-score-element element tempo param-obj view 
                              :level 1
                              :position i
                              :y-shift y-shift
                              :font-size font-size
                              :selection selection))
    ))

;;;========================
;;; BEAMING / GROUPS
;;;========================

;;; select up or down according to the mean-picth in this group vs. center of the current staff
;;; accordingly, the beam-point is <beam-size> above max pitch, or below min-pitch
(defmethod find-group-beam-line ((self group) staff)
  
  (let* ((medium (staff-medium-pitch staff))
         (chords (get-all-chords self)) ;;; can be nil if only rests !!
         (pitches (loop for c in chords append (mapcar 'midic (inside c))))
         (p-max (list-max pitches)) (p-min (list-min pitches))
         (mean (if pitches 
                   ;(/ (apply '+ pitches) (length pitches)) 
                   (* (+ p-max p-min) .5)
                 7100)) ;;; default = B4
         (max-beams (list-max (mapcar #'(lambda (c) 
                                              (get-number-of-beams (symbolic-dur c)))
                                          chords))))
    ;(print max-beams)
    (if (<= mean medium) 
        ;;; up
        (values (+ (pitch-to-line p-max) *stem-height* (* max-beams .5)) :up)
      ;;; down
      (values (- (pitch-to-line p-min) *stem-height* (* max-beams .5)) :down)
      )
    ))


(defun find-group-symbol (val)
  (let* ((den (denominator val))
         (bef (bin-value-below den)))
    (list 
     (note-strict-beams (/ 1 bef)) 
     (denominator (/ bef den)))))

(defun note-strict-beams (val)
   (cond
    ((or (= val 1/4) (= val 1/2) (>= val 1)) 0)
    ((= val 1/8)  1)
    ((= val 1/16) 2)
    ((= val 1/32) 3)
    ((= val 1/64) 4)
    ((= val 1/128) 5)
    ((= val 1/256) 6)
    ((= val 1/512) 7)
    ((is-binaire? val) (round (- (log (denominator val) 2) 2)))
    (t (find-group-symbol val))))

;;; gives number of beams for a given division
;;; might return a list if the denominator is not a power of two
;;; => entry in the process of determining the beaming for a given chord.
;;; this code is directly adapted from OM6 score editors
(defun get-beaming (val)
  
  (let* ((num (numerator val))
         (den (denominator val))
         (bef (bin-value-below num)))
    
     (cond
      ((= bef num)
       (note-strict-beams (/ num den)))
      
      ((= (* bef 1.5) num)
       (note-strict-beams (/ bef den)))
       
      ((= (* bef 1.75) num)
       (note-strict-beams (/ bef den)))

      (t 0))
     ))


(defun get-number-of-beams (val)
  (let ((beams (get-beaming val)))
    (if (listp beams) (car beams) beams)))
  

(defmethod beam-num ((self score-object) dur)
  (get-number-of-beams dur))

;;; gets the minimum number of beams in a group
(defmethod beam-num ((self group) dur)
 
  (let ((nd (or (numdenom self) (list 1 1))))  
    ;; (print (list "G" (tree self) (numdenom self) (symbolic-dur self) dur (get-group-ratio (tree self))))
    
    (loop for element in (inside self)
          minimize (beam-num element (* (/ (car nd) (cadr nd)) 
                                        (/ (symbolic-dur element) (symbolic-dur self)) 
                                        dur)))
    ))


;;; Get the depth of num/dem line in a group
(defmethod calcule-chiff-level ((self t)) 0)
(defmethod calcule-chiff-level ((self group))
  (+ (if (numdenom self) 1 0) 
     (loop for item in (inside self)
           maximize (calcule-chiff-level item))))

                     
;;; beam-info : (beam-pos beam-direction beams-already-drawn current-unit)
(defmethod draw-score-element ((object group) tempo param-obj view 
                               &key font-size (y-shift 0) (level 1) position beam-info selection)
  
  (declare (ignore position))
  
  ;(print (list "=========="))
  ;(print (list "GROUP" (tree object) (numdenom object) (symbolic-dur object)))

  (let* ((staff (get-edit-param param-obj :staff))
         (beam-n-and-dir (or (first-n beam-info 2) ;; the rest of the list is local info
                             (multiple-value-list (find-group-beam-line object staff))))
         (beams-from-parent (nth 2 beam-info))
         ;; (r-unit (or (nth 3 beam-info) 1))
         (nd (or (numdenom object) (list 1 1)))
         (chords (get-all-chords object))
         (pix-beg (time-to-pixel view (beat-to-time (symbolic-date (car chords)) tempo) ))
         (pix-end (time-to-pixel view (beat-to-time (symbolic-date (car (last chords))) tempo) ))
         
         (n-beams (beam-num object (symbolic-dur object)))
         (beams (arithm-ser 1 n-beams 1)))
         
    
    ;(print (list "=>" (tree object) "=" n-beams))
    
    ;; the first group catching a beam information transfers to all descendants  
    (loop for element in (inside object)
          for i from 0 do
          (draw-score-element element tempo param-obj view 
                              :y-shift y-shift
                              :font-size font-size
                              :level (1+ level) 
                              :beam-info (when beam-n-and-dir (list 
                                                               (nth 0 beam-n-and-dir)
                                                               (nth 1 beam-n-and-dir)
                                                               beams  ;;; send the beams already drawn in 3rd position
                                                               ;; (/ (symbolic-dur object) (cadr nd))
                                                               ))
                              :position i
                              :selection selection))

    ;;; sub-groups or chords wont have to draw these beams
    (draw-beams pix-beg pix-end
                (car beam-n-and-dir)  ;; the beam init line
                (cadr beam-n-and-dir) ;; the beam direction
                (set-difference beams beams-from-parent)   ;; the beam numbers 
                y-shift staff font-size)
   
    ;;; subdivision line and numbers 
    (when (numdenom object)
      (let* ((numdenom-level (calcule-chiff-level object)))
        ;;; chiflevel tells us how much above or below the beam this should be placed
        ;; (print (list object chiflevel (numdenom object)))
        (draw-group-div (numdenom object)
                        numdenom-level
                        pix-beg pix-end
                        (car beam-n-and-dir)  ;; the beam init line
                        (cadr beam-n-and-dir) ;; the beam direction
                        y-shift staff font-size)
        ))
    )
  )



#|
;;; passed through groups as "durtot" in OM6:
;;; starting at (* symb-beat-val factor) in measure

 (real-beat-val (/ 1 (fdenominator (first tree))))
 (symb-beat-val (/ 1 (find-beat-symbol (fdenominator (first tree)))))
 (dur-obj-noire (/ (extent item) (qvalue item)))
 (factor (/ (* 1/4 dur-obj-noire) real-beat-val))
 (unite (/ durtot denom))
;;; => 
(if (not group-ratio) 
     (let* ((dur-obj (/ (/ (extent item) (qvalue item)) 
                        (/ (extent self) (qvalue self)))))
       (* dur-obj durtot))
   (let* ((operation (/ (/ (extent item) (qvalue item)) 
                        (/ (extent self) (qvalue self))))
          (dur-obj (numerator operation)))
     (setf dur-obj (* dur-obj (/ num (denominator operation))))
     (* dur-obj unite)))

;;; passed through groups as "ryth"
;;; starting at  (list real-beat-val (nth i (cadr (tree self)))) in measure
;;; => 
(list (/ (car (second ryth)) (first ryth))
      (nth i (cadr (second ryth))))

|#


;;;===================
;;; CHORD
;;;===================

(defmethod draw-score-element ((object chord) 
                               tempo param-obj view 
                               &key font-size (y-shift 0) (level 1) (position 0) beam-info selection)
  

  (let* ((begin (beat-to-time (symbolic-date object) tempo))
         
         (staff (get-edit-param param-obj :staff))
         (chan (get-edit-param param-obj :channel-display))
         (vel (get-edit-param param-obj :velocity-display))
         (port (get-edit-param param-obj :port-display))
         (dur (get-edit-param param-obj :duration-display))

         ;;; from OM6.. 
         (beams-num (get-number-of-beams (symbolic-dur object)))
         (beams-from-parent (nth 2 beam-info))
         (beams-to-draw (set-difference (arithm-ser 1 beams-num 1) beams-from-parent))
         ;;(propre-group (if (listp beams) (cadr beams)))
         )
    
    ;; (print (list "chord" (symbolic-dur object) beams))
    ;; in fact propre-group (= when a standalone chord has a small group indication) will never happen (in OM)
    
    (setf 
     (b-box object)
     (draw-chord object
                 (time-to-pixel view begin)
                 y-shift 
                 (w view) (h view) 
                 font-size
                 :head (multiple-value-list (note-head-and-points (symbolic-dur object)))
                 :stem (or (= level 1) (car beam-info))  ;; (car beam-info) is the beam-line 
                 :beams (list beams-to-draw position)
                 :staff staff
                 :draw-chans chan
                 :draw-vels vel
                 :draw-ports port
                 :draw-durs dur
                 :selection (if (find object selection) T selection)
                 :build-b-boxes t
                 ))
    
    

    ))




;;;===================
;;; CONTINUATION-CHORD
;;;===================

(defmethod draw-score-element ((object continuation-chord) 
                               tempo param-obj view 
                               &key font-size (y-shift 0) (level 1) (position 0) beam-info selection)
  

  (let* ((begin (beat-to-time (symbolic-date object) tempo))
         (staff (get-edit-param param-obj :staff))
         
         ;;; from OM6.. 
         (beams-num (get-number-of-beams (symbolic-dur object)))
         (beams-from-parent (nth 2 beam-info))
         (beams-to-draw (set-difference (arithm-ser 1 beams-num 1) beams-from-parent))
         ;;(propre-group (if (listp beams) (cadr beams)))
         )
       
    (setf 
     (b-box object)
     (draw-chord (previous-chord object)
                 (time-to-pixel view begin)
                 y-shift 
                 (w view) (h view) 
                 font-size
                 :head (multiple-value-list (note-head-and-points (symbolic-dur object)))
                 :stem (or (= level 1) (car beam-info))  ;; (car beam-info) is the beam-line 
                 :beams (list beams-to-draw position)
                 :staff staff
                 :selection (if (find (previous-chord object) selection) T selection)
                 :build-b-boxes nil
                 ))
    
    (draw-tie object view font-size tempo)
    
    ))



(defmethod draw-tie ((object t) view font-size tempo) nil)
 
(defmethod draw-tie ((object continuation-chord) view font-size tempo)
  ;;; draw a tie with the previous-chord
  
  (let* ((unit (font-size-to-unit font-size))
         (tie-h (* unit 1))
         (x2 (time-to-pixel view (beat-to-time (symbolic-date object) tempo))))

    (om-with-line-size (* *stemThickness* unit 1.8)

      (loop for n1 in (inside (previous-chord object))
            do
            (if (equal (get-tie-direction n1 (previous-chord object)) :down)
                
                (om-draw-arc (b-box-x2 (b-box n1))  ;; x1
                             (- (b-box-y2 (b-box n1)) tie-h) ;; y1
                             (- x2 (b-box-x2 (b-box n1)))
                             (+ (- (b-box-y2 (b-box n1)) (b-box-y1 (b-box n1))) tie-h)
                             0 (- pi))
              
              ;;; up
              (om-draw-arc (b-box-x2 (b-box n1))  ;; x1
                           (- (b-box-y1 (b-box n1)) tie-h);; y1
                           (- x2 (b-box-x2 (b-box n1))) 
                           (+ (- (b-box-y2 (b-box n1)) (b-box-y1 (b-box n1))) tie-h) 
                           0 pi)
              )
            
            ;(om-draw-rect (b-box-x2 (b-box n1)) ;; x1
            ;              (- (b-box-y2 (b-box n1)) tie-h) ;; y1
            ;              (- x2 (b-box-x2 (b-box n1))) 
            ;              (+ (- (b-box-y2 (b-box n1)) (b-box-y1 (b-box n1))) tie-h)
            ;              :color (om-def-color :red))
            )
      )
    ))


(defmethod get-tie-direction ((self note) (parent chord))
  (let* ((m (midic self))
         (m-list (sort (lmidic parent) '<)))
    (if (>= (position m m-list :test '=) (ceiling (length m-list) 2))
        :up :down)))


;;;=========
;;; REST
;;;=========

(defmethod draw-score-element ((object r-rest) tempo param-obj view &key font-size (y-shift 0) (level 1) position beam-info selection)
  
  (let* ((begin (beat-to-time (symbolic-date object) tempo)))
        
    (setf 
     (b-box object)
     (draw-rest object
                (time-to-pixel view begin)
                y-shift 
                (w view) (h view) 
                font-size 
                :head (multiple-value-list (rest-head-and-points (symbolic-dur object)))
                :staff (get-edit-param param-obj :staff)
                :selection (if (find object selection) T selection)
                :build-b-boxes t
                ))
    ))



;;; todo
;;; LONG-HEAD (see draw-chord)
;;; RESTS: GROUPS/BEAMING AND Y-POSITIONS
;;; TIES
;;; TEMPO / CHIFFRAGE MESURE
;;; SPACING
;;; TEMPO CHANGE
;;; Grace notes


