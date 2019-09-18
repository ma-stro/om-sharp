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

;=========================================================================
;;; SIMPLE VALUE BOX
;;;====================================================

(in-package :om)

(defclass OMValueBox (OMBoxCall) ()
  (:metaclass omstandardclass)
  (:default-initargs :icon-pos :noicon))

(defmethod get-object-type-name ((self OMValueBox)) "Simple value")

(defmethod get-properties-list ((self OMValueBox))
  (hide-properties (call-next-method) '(:group-id :lambda)))

(defmethod create-box-outputs ((self OMValueBox))
  (list (make-instance 'box-output :box self :name "value")))

(defmethod next-optional-input ((self OMValueBox)) t)

(defmethod more-optional-input ((self OMValueBox) &key name (value nil val-supplied-p) doc reactive)

  (declare (ignore name doc))

  (unless nil ; (inputs self)
    (add-optional-input self :name "in" :value (if val-supplied-p value nil) :doc "set box value" :reactive reactive)
    t))

(defmethod omNG-make-new-boxcall ((reference (eql 'value)) pos &optional init-args)
  (let* ((box (make-instance 'OMValueBox
                            :name "value box"
                            :reference (type-of init-args)
                            ;;; by default these boxes are white..
                            :color (make-color-or-nil :color (om-def-color :white) :t-or-nil t)
                            )))
    (setf (value box) (list init-args)
          (box-x box) (om-point-x pos)
          (box-y box) (om-point-y pos)
          (inputs box) nil)
    (let ((size (om-max-point (minimum-size box) (default-size box))))
      (setf (box-w box) (om-point-x size)
            (box-h box) (om-point-y size)))
    box))


(defmethod print-value ((self OMValueBox)) 
  (format nil "~s" (car (value self))))

(defmethod object-name-in-inspector ((self OMValueBox)) "value box")

(defmethod get-documentation ((self OMValueBox)) 
  (format 
   nil 
   "Current value of type ~A.~%~%Use +/- to add/remove inputs.~%Double-click to edit contents." 
   (string-upcase (reference self))))


(defmethod default-size ((self OMValueBox))
  (multiple-value-bind (tw th)
      (om-string-size (print-value self) (box-draw-font self))
    (om-make-point (max (min (+ tw 18) 500)
                        (+ 20 (* (length (inputs self)) 10))
                        32)
                   (+ th 16))))

(defmethod maximum-size ((self OMValueBox))
  (omp 1000 1000))

(defmethod minimum-size ((self OMValueBox))
  (multiple-value-bind (tw th)
      (om-string-size (print-value self) (box-draw-font self))
    (om-make-point (max ; (+ tw 18)
                        (+ 20 (* (length (inputs self)) 10))
                        32)
                   (max (+ th 16) 28))))

(defmethod allow-text-input ((self OMValueBox)) 
  (values (format nil "~s" (car (value self)))
          #'(lambda (box text)
                   (handler-bind ((error #'(lambda (error) (declare (ignore error)) (om-beep) (om-abort)))) 
                     ;;(setf (name box) text)
                     (let ((val (ignore-errors (read-from-string text))))
                       (store-current-state-for-undo (editor (container self)))
                       (set-value box (list (if (quoted-form-p val) (eval val) val)))
                       )))
          ))

(defmethod om-copy ((self OMValueBox)) 
  (let ((newbox (call-next-method)))
    ;;; add the optional/keywords
    (setf (value newbox) (om-copy (value self)))
    newbox))


(defmethod initialize-box-value ((self OMValueBox) &optional value) nil)

(defmethod editable-on-click ((self OMValueBox)) nil)


(defmethod get-object-slots-for-undo ((self OMValueBox)) 
  (append (call-next-method) '(value)))


;;;========================
;;; BOX FRAME
;;;========================

(defclass OMValueBoxFrame (OMBoxFrame) ())

(defmethod get-box-frame-class ((self OMValueBox)) 'OMValueBoxFrame)

(defmethod display-text-and-area ((self OMValueBoxFrame))
  (let ((font (or (font-font (text-font (object self))) (om-get-font self))))
    (multiple-value-bind (w h) (om-string-size (print-value (object self)) font)
      (values (print-value (object self)) 
              (case (box-draw-text-align (object self))
                    (:center (round (- (/ (w self) 2) (/ w 2))))
                    (:right (- (w self) w 8))
                    (otherwise 6))
              6 
              w h))))


;;; drag-edit
(defmethod om-view-click-handler ((self OMValueBoxFrame) position)
         
  (if (and (numberp (get-box-value (object self)))
           (or (om-command-key-p)
               (container-frames-locked (om-view-container self))))
    
        (let* ((box (object self))
               (curr-val (get-box-value box))
               (ndec (multiple-value-bind (i d)
                         (string-until-char (format nil "~D" curr-val) ".")
                       (length d)))
               (fact (expt 10 ndec)))
          
          ;;; we use fact to perfom integer arithmetics and avoid floating point approximations

          (store-current-state-for-undo (editor (container box)))
          
          (om-init-temp-graphics-motion self position nil 
                                        :motion #'(lambda (view pos)
                                                    (let ((diff (- (om-point-y position) (om-point-y pos))))
                                                      (when (om-shift-key-p) (setf diff (* diff 10)))
                                                      (setf curr-val (/ (+ (* curr-val fact) diff) fact))
                                                      (setf position pos)
                                                      (set-value box (list curr-val))
                                                      (om-invalidate-view view)
                                                      ))
                                        )
          )
      
      (call-next-method)))



(defmethod om-view-doubleclick-handler ((self OMValueBoxFrame) position)
  (unless (edit-lock (editor (om-view-container self)))
    (or (apply-in-area self 'click-in-area position)
        (multiple-value-bind (edittext action)
            (allow-text-input (object self))
          (let* ((container-view (om-view-container self)))
            (edit-text-in-patch edittext self container-view action (omp 0 0) (omp (w self) (h self))
                                :auto-resize nil :multi-line t)
            t)))))

