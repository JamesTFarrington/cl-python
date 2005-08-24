(in-package :python)

;;;; Python classes and metaclasses; the built-in classes including
;;;; their methods.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Class frameword:  py-meta-type, py-type, py-dictless-object

(eval-when (compile load eval)
(defvar *warn-making-dict* nil)
)

(eval-when (compile load eval)
(defun dict-init-func ()
  (when *warn-making-dict*
    (break "making dict..."))
  (make-hash-table :test #'eq))
)

(defclass py-dict-mixin ()
  ((dict :initarg :dict :initform (dict-init-func) :accessor dict)))

(defmethod dict ((x symbol)) ;; (dict <symbol>) is designator for (dict <class>)
  (break "dict symbol: ~A" x)
  (dict (find-class x)))

(defmethod dict ((x t))
  nil)

(defun dict-get (x key)
  (let ((d (dict x)))
    (assert d () "dict-get: object ~A has no dict (key ~A)" x key)
    (gethash key (dict x))))

(defun dict-del (x key)
  (remhash (dict x) key))

(defun (setf dict-get) (new-val x key)
  (setf (gethash key (dict x)) new-val))


(defclass py-class-mixin (py-dict-mixin)
  ((mro :initarg :mro :accessor class-mro)))


;; Python metatype. Class `type' and subclasses thereof are instances
;; of py-meta-type.

(defclass py-meta-type (py-class-mixin standard-class)
  ())

(defmethod initialize-instance :after ((cls py-meta-type) &rest initargs)
  (declare (ignore initargs))
  (mop:finalize-inheritance cls))

#+(or)
(defmethod make-instance
    ((cls (eql (find-class 'py-meta-type))) &rest initargs)
  ;; Create a new Python metatype, i.e. subclass of `type'
  TODO)


;; A class for Python classes. This is an instance of py-meta-type

(defclass py-type (py-class-mixin standard-class)
  ()
  (:metaclass py-meta-type))

(defmethod initialize-instance :after ((cls py-type) &rest initargs)
  (declare (ignore initargs))
  (mop:finalize-inheritance cls))

#+(or)
(defmethod make-instance ((cls py-meta-type) &rest initargs)
  ;; Create a new Python class that has CLS as metaclass
  TODO)

#+(or)
(defmethod compute-class-precedence-list ((cls py-meta-type))
  ;; Compute CPL of new Python class
  TODO)

#+(or)
(defmethod allocate-instance ((cls py-type) &rest initargs) 
  ;; __new__
  TODO)

#+(or)
(defmethod initialize-instance ((cls py-type) &rest initargs)
  ;; Initialize a Python class
  ;;  - call __init__ method
  TODO)


;; Python classes are instances of (a subclass of) python-type

(defclass py-dictless-object (standard-object)
  ()
  (:metaclass py-type))

(mop:finalize-inheritance (find-class 'py-dictless-object))

(defclass py-object (py-dict-mixin py-dictless-object)
  ()
  (:metaclass py-type))

(mop:finalize-inheritance (find-class 'py-object))


;; Core type/object

(defclass py-core-object (py-dictless-object) ())
(defclass py-core-type   (py-type)   ())

;; User type/object

(defclass py-user-type   (py-type) ())
(defclass py-user-object (py-object)
  ()
  (:metaclass py-user-type))

;; Lisp type/object

(defclass py-lisp-type (py-type)
  ()
  (:documentation "Metaclass for proxy classes"))

(defclass py-lisp-object (py-dictless-object)
  ((lisp-object :initarg :lisp-object :accessor proxy-lisp-val))
  (:metaclass py-lisp-type)
  (:documentation "Base class for proxy classes"))


#+(or)
(defmethod make-instance ((cls py-type) &rest initargs)
  ;; Create an instance of a Python class.
  TODO)

#+(or)
(defmethod initialize-instance ((x py-dictless-object) &rest initargs)
  ;; Initialize a simple instance of a Python class.
  TODO)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; dynamic class creation

(defun make-py-class (&key name namespace supers cls-metaclass mod-metaclass)
  (assert (symbolp name))
  (assert (listp supers))
  (assert (hash-table-p namespace))

  ;; XXX is this a true restriction?  Custom metaclasses may allow
  ;; more kinds of `bases' in their __new__(...) ?
  
  ;; either:
  ;;  1) all supers are subtype of 'py-type   (to create a new metaclass)
  ;;  2) all supers are subtype of 'py-dictless-object (to create new "regular user-level" class)
  
  (flet ((of-type-class (s) (typep s 'class))
	 (subclass-of-py-dl-object-p (s) (subtypep s 'py-dictless-object))
	 (subclass-of-py-type-p   (s) (subtypep s 'py-type)))
    
    (unless (every #'of-type-class supers)
      (py-raise 'TypeError "Not all superclasses are classes (got: ~A)." supers))

    (loop for s in supers
	unless (or (subclass-of-py-type-p s)
		   (subclass-of-py-dl-object-p s))
	do (error "BUG? Superclass ~A is neither sub of 'type nor sub of 'object!" s))
    
    (let ((core-supers (remove-if-not (lambda (s) (typep s 'py-core-type)) supers)))
      (when core-supers
	(py-raise 'TypeError "Cannot subclass from these classes: ~A" core-supers)))
    
    (when (and (some #'subclass-of-py-type-p supers)
	       (some #'subclass-of-py-dl-object-p supers))
      (py-raise 'TypeError "Superclasses are at different levels (some metaclass, ~
                            some regular class) (got: ~A)." supers))
    

    ;; Python class `object' corresponds to Lisp class 'py-dictless-object
    ;; but the new class should have a dict:
    
    (substitute (load-time-value (find-class 'py-object))
		(load-time-value (find-class 'py-dictless-object))
		supers)
    
    
    (let ((metaclass (or cls-metaclass
			 (when supers (class-of (car supers)))
			 mod-metaclass
			 (load-time-value (find-class 'py-type)))))
      
      (warn "metaclass: ~A" metaclass)
      
      (unless (typep metaclass 'class)
	(py-raise 'TypeError "Metaclass must be a class (got: ~A)" metaclass))
      
      (unless (or (eq metaclass (load-time-value (find-class 'py-meta-type)))
		  (subtypep metaclass 'py-type))
	(py-raise 'TypeError 
		  "Metaclass must be subclass of `type' (got class: ~A)" metaclass))
      

      ;; When inheriting from py-lisp-type (like `int'), use
      ;; py-user-type as metaclass.
      ;; XXX subclassing `function' ?
      
      (when (member metaclass
		    (load-time-value (list (find-class 'py-lisp-type))
					   (find-class 'py-core-type)))
	(setf metaclass (load-time-value (find-class 'py-user-type))))
      
      
      ;; Subclass of `type' has metaclass 'py-meta-type
      
      (when (eq metaclass (load-time-value (find-class 'py-meta-type)))
	(let ((cls (mop:ensure-class
		    name
		    :direct-superclasses supers
		    :metaclass (load-time-value (find-class 'py-meta-type)))))
	  (return-from make-py-class cls)))
      
      
      ;; Not a subclass of `type', so at the `object' level
      
      (let ((__new__ (recursive-class-dict-lookup metaclass '__new__)))
	
	(assert __new__ ()
	  "recur: no __new__ found for class ~A, yet it is a subclass of PY-TYPE ?!"
	  metaclass)

	(let ((bound-_new_ (and __new__ 
				(bind-val __new__ metaclass (py-class-of metaclass)))))

	  (assert bound-_new_ () "bound __new__ failed")
	  (warn "Calling this __new__ method: ~S" bound-_new_)
	  
	  ;; If __new__ is a static method, then bound-_new_ will
	  ;; be the underlying function.
	  
	  (let ((cls (py-call bound-_new_ metaclass name supers namespace)))
	    
	    (warn "The __new__ method returned class: ~S" cls)
	    (assert cls () "__new__ returned NIL: ~A" bound-_new_)
	    
	    ;; Call __init__ when the "thing" returned by
	    ;; <metaclass>.__new__ is of type <metaclass>.
	    
	    (if (typep cls metaclass)
		
		(let ((__init__ (recursive-class-dict-lookup metaclass '__init__)))
		  (if __init__
		      (progn (warn "  __init__ method is: ~A" __init__)
			     (py-call __init__ cls))
		    (warn "No __init__ found, for class ~A returned by metaclass ~A"
			  cls metaclass)))
	      
	      (warn "Not calling __init__ method, as class ~A is not instance of metaclass ~A"
		    cls metaclass))
	    
	    cls))))))
	  
	  
	  
	   


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Built-in Python object types:
;;; 
;;; -- type ----------- repr ----- subclassable -- examples -------------------
;;;  py-lisp-object:  lisp value    yes       number, string, tuples, vectors, dict
;;;  py-core-object:  py cls inst   no        function, method
;;;  py-user-object:  py cls inst   yes       file, module, property
;;;

;;; Support methods on built-in Python classes

(defmacro def-py-method (cls.meth &rest args)
  (let* ((cm (symbol-name cls.meth))
	 (dot-pos (or (position #\. cm)
		      (error "Need dot in name: (def-py-method classname.methodname ..); got: ~A"
			     cls.meth)))
	 (cls  (intern (subseq cm 0 dot-pos) #.*package*))
	 (meth (intern (subseq cm (1+ dot-pos)) #.*package*))
	 (modifiers (loop while (keywordp (car args)) collect (pop args))))

    (assert (<= (length modifiers) 1) ()
      "Multiple modifiers for a py-method: ~A. Todo?" modifiers)

    `(progn
       ,(destructuring-bind (func-args &body func-body) args
	  (loop with real-args
	      with body = `(locally ,@func-body) ;; allows DECLARE forms at head

	      for sym in func-args
	      for sym-name = (when (symbolp sym) (symbol-name sym))

	      if (not (symbolp sym))
	      do (push sym real-args)
		 
	      else if (char= #\^ (aref sym-name (1- (length sym-name))))
	      do (let ((real-name (intern (subseq sym-name 0 (1- (length sym-name)))
					  #.*package*)))
		   (push real-name real-args)
		   (setf body `(let ((,real-name (deproxy ,real-name)))
				 ,body)))
		 
	      else do (push sym real-args)
		   
	      finally (return `(defun ,cls.meth ,(nreverse real-args)
				 (block ,cls.meth
				   ,body)))))
       
       (let* ((cls (or (find-class ',cls) (error "No such class: ~A" ',cls))))
	 (unless (dict cls)
	   (error "Class ~A has no dict" cls))
	 (setf (dict-get cls ',meth)
	   ,(ecase (car modifiers)
	      ((nil)               `(function ,cls.meth))
	      (:static             `(make-instance 'py-static-method
				      :func (function ,cls.meth)))
	      (:attribute          `(make-instance 'py-attribute-method
				      :func (function ,cls.meth)))))))))

(defconstant *the-true* 1)
(defconstant *the-false* 0)

(defvar *the-none*)
(defvar *the-ellipsis*)
(defvar *the-notimplemented*)
    
(defun py-bool (lisp-val)
  (if lisp-val *the-true* *the-false*))

(define-compiler-macro py-bool (lisp-val)
  `(if ,lisp-val *the-true* *the-false*))

;;; Attributes are a fundamental thing: getting, setting, deleting

(defgeneric py-attr (x attr)
  (:documentation "Get attribute ATTR of X"))

(defgeneric (setf py-attr) (val x attr)
  (:documentation "Set attribute ATTR of X to VAL"))


;; By default, when an object has a dict, attributes are looked up in
;; the dict.

#+(or);; attributs classes should go via metatype, not directly like this
(defmethod py-attr ((x py-dict-mixin) attr)
  (if (typep x 'class)
      (recursive-class-dict-lookup x attr)
    (dict-get x attr)))

;; allowed for now...
(defmethod (setf py-attr) (val (x py-dict-mixin) attr)
  (setf (dict-get x attr) val))

#+(or)
(defmethod py-del-attr ((x py-dict-mixin) attr)
  (dict-del x attr))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Core objects (function, method, None...; not subclassable by the user)



;; Function (Core object)

(defclass py-lisp-function (py-core-object)
  ()
  (:metaclass py-core-type))

(mop:finalize-inheritance (find-class 'py-lisp-function))

(def-py-method py-lisp-function.__repr__ (func)
  (with-output-to-string (s)
    (print-object func s)))

(def-py-method py-lisp-function.__get__ (func inst cls)
  (if (and inst (not (eq inst *the-none*)))
      (make-instance 'py-bound-method :instance inst :func func)
    (if (and cls (not (eq cls *the-none*)))
	(make-instance 'py-unbound-method :class cls :func func)
      (py-raise 'ValueError
		"Method function.__get__(self, inst, cls) must be called with at ~
                 least one of inst or cls arguments not-none (got: ~A ~A ~A)"
		func inst cls))))

(defclass funcallable-python-class (mop:funcallable-standard-class py-core-type)
  ;; When subclassable python classes also get such a metatype,
  ;; s/py-core-type/py-type/
  ())

(defclass py-function (standard-generic-function py-core-object py-dict-mixin)
  ;; mop:funcallable-standard-class defines :name initarg, but I don't know how to access it...
  ((name :initarg :name :accessor py-function-name))
  (:metaclass funcallable-python-class))

(defmethod make-py-function ((name symbol) (f function))
  (let ((x (make-instance 'py-function :name name)))
    (mop:set-funcallable-instance-function x f)
    ;; fill dict?
    x))

(def-py-method py-function.__get__ (func obj class)
  (if (none-p obj)
      (make-instance 'unbound-method :func func :class class)
    (make-instance 'bound-method :func func :instance obj)))

(def-py-method py-function.__repr__ (func)
  (with-output-to-string (s)
    (print-unreadable-object (func s :identity t)
      (format s "python-function ~A" (py-function-name func)))))

;; Method (Core object)

(defclass py-method (py-core-object)
  ((func :initarg :func :accessor py-method-func))
  (:metaclass py-core-type))

(def-py-method py-method.__get__ (func obj class)
  (declare (ignore obj class))
  func)

(defclass py-bound-method (py-method)
  ((instance :initarg :instance :accessor py-method-instance))
  (:metaclass py-core-type))

(def-py-method py-bound-method.__repr__ (x)
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t :type t)
      (with-slots (instance func) x
	(format s "~A.~A" instance func)))))

(def-py-method py-bound-method.__call__ (x &rest args)
  (with-slots (func instance) x
    (apply #'py-call func instance args)))

(defclass py-unbound-method (py-method)
  ((class :initarg :class :accessor py-method-class))
  (:metaclass py-core-type))


(defclass py-static-method (py-method)
  ()
  (:metaclass py-core-type))

(def-py-method py-static-method.__get__ (x inst class)
  (declare (ignore inst class))
  (slot-value x 'func))

(def-py-method py-static-method.__repr__ (x)
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t)
      (format s "the static method ~A" (slot-value x 'func)))))

(def-py-method py-static-method.__call__ (x &rest args)
  (apply #'py-call (slot-value x 'func) args))

(defmethod print-object ((x py-static-method) stream)
  (print-unreadable-object (x stream :identity t :type t)
    (format stream ":func ~A" (slot-value x 'func))))
    

(defclass py-class-method (py-method)
  ((class :initarg :class))
  (:metaclass py-core-type))

(defclass py-attribute-method (py-method)
  ()
  (:metaclass py-core-type))

(def-py-method py-attribute-method.__get__ (x inst class)
  (declare (ignore class))
  (if inst
      (py-call (slot-value x 'func) inst)
    nil))

(def-py-method py-attribute-method.__set__ (x inst class)
  (if inst
      (py-raise 'TypeError
		"Attribute ~A of object ~A is read-only (value: ~A)"
		x inst (py-call (slot-value x 'func) inst))
    (py-raise 'TypeError
	      "Class ~A has no attribute ~A" class x)))

(def-py-method py-attribute-method.__repr__ (x)
  (with-output-to-string (s)
    (print-unreadable-object (x s :type t :identity t))))

(defclass py-enumerate (py-core-object)
  ((gener :initarg :gener))
  (:metaclass py-core-type))

(mop:finalize-inheritance (find-class 'py-enumerate))

(def-py-method py-enumerate.__new__ :static (cls iterable)
	       (assert (subtypep cls 'py-enumerate))
	       (let ((gener (make-iterator-from-function
			     :name :enumerater
			     :func (let ((iter (get-py-iterate-fun iterable))
					 (i 0))
				     (lambda ()
				       (let ((val (funcall iter)))
					 (when val
					   (prog1 
					       (make-tuple-from-list (list i val))
					     (incf i)))))))))
		 (make-instance cls) :gener gener))

(def-py-method py-enumerate.__repr__ (x)
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t :type t))))


(defclass py-slice (py-core-object)
  ()
  (:metaclass py-core-type))

(defclass py-super (py-core-object) ;; subclassable?
  ()
  (:metaclass py-core-type))


(defclass py-xrange (py-core-object)
  (start stop step)
  (:metaclass py-core-type))

(mop:finalize-inheritance (find-class 'py-xrange))

(def-py-method py-xrange.__init__ (x &rest args)
  (with-slots (start stop step) x
    (setf start nil
	  stop nil
	  step nil)
    (ecase (length args)
      (0 (py-raise 'TypeError "xrange: >= 1 arg needed"))
      (1 (unless (> (car args) 0)
	   (break "xrange: invalid only val: ~A" (car args)))
	 (setf start 0 
	       stop (car args)
	       step 1))
      (2 (break "xrange 2 todo"))
      (3 (break "xrange 3 todo")))))

(def-py-method py-xrange.__iter__ (x^)
  (with-slots (start stop step) x
    (let ((i start))
      (make-iterator-from-function :name :xrange-iterator
				   :func (lambda ()
					   (unless (>= i stop)
					     (prog1 i
					       (incf i step))))))))

(def-py-method py-xrange.__str__ (x^)
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t :type t)
      (with-slots (start stop step) x
	(format s ":start ~A :stop ~A :step ~A" start stop step)))))
;; None

(defclass py-none (py-core-object) () (:metaclass py-core-type))
(setf *the-none* (make-instance 'py-none))
(defun none-p (x) (eq x *the-none*))

(def-py-method py-none.__repr__ (x)
  (declare (ignore x))
  "None")
   
;; Ellipsis

(defclass py-ellipsis (py-core-type) () (:metaclass py-core-type))
(setf *the-ellipsis* (make-instance 'py-ellipsis))

;; NotImlemented
(defclass py-notimplemented (py-core-type) () (:metaclass py-core-type))
(setf *the-notimplemented* (make-instance 'py-notimplemented))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; User objects (Object, Module, File, Property)



;; Object (User object)

(defun bind-val (val x x.class)
  (let ((get-meth (recursive-class-dict-lookup
		   (py-class-of val) '__get__)))
    (if get-meth
	(py-call get-meth val x x.class)
      val)))

(def-py-method py-object.__getattribute__ (x attr)
  (let ((class-attr-val   nil)
	(__getattr__      nil)
	(x.class          (py-class-of x)))
    
    #+(or)(break "po.__getattr..__ ~A ~A    cpl=~A"
		 x attr (mop:class-precedence-list x.class))
    
    (loop for c in (mop:class-precedence-list x.class)
	until (or (eq c (load-time-value (find-class 'standard-class)))
		  (eq c (load-time-value (find-class 'py-dict-mixin)))
		  (eq c (load-time-value (find-class 'py-class-mixin))))
	      
	for c.dict = (dict c) ;; may be NIL
		     
	when c.dict
	do (let ((getattribute-meth (gethash '__getattribute__ c.dict)))
	     (when (and getattribute-meth
			(not (eq getattribute-meth #'py-object.__getattribute__)))
	       (return-from py-object.__getattribute__
		 (py-call getattribute-meth x attr))))
	   
	   (unless class-attr-val
	     (let ((val (gethash attr c.dict)))
	       (when val 
		 (setf class-attr-val val))))
	   
	   (unless (or class-attr-val __getattr__)
	     (let ((getattr-meth (gethash '__getattr__ c.dict)))
	       (when getattr-meth (setf __getattr__ getattr-meth)))))

    ;; Arriving here means: no __getattribute__, but perhaps
    ;; __getattr__ or class-attr-val.
    
    ;; A class attribute that is a data descriptor (i.e. has a
    ;; `__set__' attribute) has higher priority than an instance
    ;; attribute.
    
    #+(or)(warn "po.__ga__: ~S" `(:class-attr-val ,class-attr-val :__getattr__ ,__getattr__))

    (when (and class-attr-val (data-descriptor-p class-attr-val))
      (return-from py-object.__getattribute__
	(bind-val class-attr-val x x.class)))
    
    ;; Try instance dict
    (when (dict x)
      (let ((val (dict-get x attr)))
	(when val
	  
	  (cond ((subtypep (py-class-of x) 'py-type)
		 
		 ;; XXX check the exact condition under which binding
		 ;; of instance dict item occurs

		 (let ((bound-val (bind-val val nil x)))
		   (when bound-val ;; attribute-method bounded to class -> NIL
		     (return-from py-object.__getattribute__ bound-val))))

		(t (return-from py-object.__getattribute__ 
		     val))))))
    
    ;; Fall back to a class attribute that is not a `data descriptor'.
    (when class-attr-val
      (return-from py-object.__getattribute__
	(bind-val class-attr-val x x.class)))
    
    ;; Fall back to the __getattr__ hook.
    (when __getattr__
      (return-from py-object.__getattribute__
	(py-call (bind-val __getattr__ x x.class) (symbol-name attr))))
    
    ;; Give up.
    (error "No such attribute: ~A . ~A" x attr)))



(def-py-method py-object.__delattr__ (x attr)
  (check-type attr symbol)
  (let ((d (dict x)))
    (cond ((null d) (py-raise 'TypeError
			      "Object ~A has not attribute `~A' (not even a dict)." 
			      x attr))
	  ((remhash attr d))
	  (t (py-raise 'ValueError "Object ~A has not attribute `~A' (but there is a dict)."
		       x attr)))))
	  

(def-py-method py-object.__new__ :static (cls &rest attr)
  (declare (ignore attr))
  (make-instance cls))

(def-py-method py-object.__init__ (&rest attr)
  (declare (ignore attr))
  ;; nothing
  )

(def-py-method py-object.__repr__ (x)
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t :type t))))

(defmethod recursive-class-dict-lookup ((cls class) attr)
  ;; Look for ATTR in class CLS and all its superclasses.
  ;; and finally (which is in this implementation not a superclass of a class).
  (loop for c in (mop:class-precedence-list cls)
      until (or (eq c (load-time-value (find-class 'standard-class)))
		(eq c (load-time-value (find-class 'py-dict-mixin))))
	    ;; XXX standard-class is after py-dict-mixin etc
      when (and (dict c) (dict-get c attr)) return it
      finally #+(or)(return nil)
	      
	      ;; this seems not needed, in the finally clause
	      (let ((obj-attr (dict-get (load-time-value (find-class 'py-object)) attr)))
		(when obj-attr
		  #+(or)(warn "rec van py-object: ~A" attr)
		  (return obj-attr)))))

(defun recursive-class-lookup-and-bind (x attr)
  #+(or)(warn "recursive-class-lookup-and-bind ~A ~A" x attr)
  (let* ((x.cls (py-class-of x))
	 (val   (recursive-class-dict-lookup x.cls attr)))
    (when val
      (bind-val val x x.cls))))
    

(def-py-method py-object.__get__ (value instance class)
  (declare (ignore instance class))
  value)

;; Type (User object)

(def-py-method py-type.__new__ :static (metacls name supers dict)
	       
	       (let* ((cls-type (if (and (some (lambda (s) (subtypep s 'py-type)) supers)
					 (eq metacls 'py-type)) ;; XXX (subtypep meta pytype)?
				    :metaclass
				  :class))
		      
		      (c (mop:ensure-class
			  name 
			  :direct-superclasses (or supers
						   (list (load-time-value (find-class 'py-user-object))))
			  :metaclass (ecase cls-type
				       (:metaclass (load-time-value (find-class 'py-meta-type)))
				       (:class     metacls)))))
		 
		 (mop:finalize-inheritance c)
		 (setf (slot-value c 'dict) dict)
		 
		 c))

(def-py-method py-type.__init__ (cls)
  (declare (ignore cls))
  nil)

(def-py-method py-type.__mro__ :attribute (x)
	       (mop:class-precedence-list x))

(def-py-method py-type.__repr__ (x) ;; XXX deproxy not needed?
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t)
      (format s "~@[meta~*~]class ~A"
	      (typep x (load-time-value (find-class 'py-meta-type)))
	      (class-name x)))))

(def-py-method py-type.__call__ (cls &rest args)
  
  (cond ((and (eq cls (load-time-value (find-class 'py-type)))
	      args
	      (not (cdr args)))
	 (return-from py-type.__call__
	   (py-class-of (car args))))
	
	((subtypep cls 'py-type)
	 ;; make a new class
	 (error "__call__ on subclass of 'type': ?  shouldn't it use type.__new__?"))
	
	((eq cls (load-time-value (find-class 'py-object)))
	 ;; object() -> an instance without __dict__
	 (return-from py-type.__call__
	   (make-instance 'py-dictless-object)))
	
	(t (let* ((__new__ (recursive-class-dict-lookup cls '__new__))
		  (inst (apply #'py-call __new__ cls args)))
	     
	     (when (typep inst cls)
	       ;; don't do this when type(x) was executed
	       (let ((__init__ (recursive-class-dict-lookup (py-class-of inst) '__init__)))
		 (apply #'py-call __init__ inst args)))
	     
	     (return-from py-type.__call__
	       inst)))))


;; Module (User object)

(defclass py-module (py-user-object) ;; no dict-mixin!?
  ((globals-names  :initarg :globals-names  :type vector :initform #())
   (globals-values :initarg :globals-values :type vector :initform #())
   (dyn-globals    :initarg :dyn-globals    :type hash-table
		   :initform (make-hash-table :test #'eq))
   (name           :initarg :name           :type symbol :initform "__main__"))
  (:metaclass py-user-type))

(defun make-module (&rest options)
  (apply #'make-instance 'py-module options))

(def-py-method py-module.__new__ :static (cls name)
	       (let ((x (make-instance cls)))
		 (setf (dict-get x '__name__) name)
		 x))
(def-py-method py-module.__init__ (&rest args)
	       (declare (ignore args))
	       nil)

(def-py-method py-module.__repr__ (x^)
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t)
      (format s "module ~A" (slot-value x 'name)))))

(defun py-string-val->symbol (attr)
  (if (symbolp attr)
      attr
    
    (let ((attr.string (if (stringp attr)
			   attr
			 (py-val->string attr))))
      
      (or (find-symbol attr.string #.*package*)
	  (intern attr.string #.*package*)))))
      
(def-py-method py-module.__getattribute__ (x^ attr)
  (let ((attr.sym (py-string-val->symbol attr)))
    
    (with-slots (name globals-names globals-values dyn-globals) x
      
      (loop for i from 0
	  for n across globals-names
	  when (eq n attr.sym) 
	  do (let ((val (svref globals-values i)))
	       (if (eq val :unbound)
		   (py-raise 'AttributeError "Module ~A has no attribute ~A" x attr.sym)
		 (return-from py-module.__getattribute__ val))))
      
      (let ((val (gethash dyn-globals attr.sym)))
	(when (and val
		   (not (eq val :unbound)))
	  (return-from py-module.__getattribute__ val)))
      
      (py-raise 'AttributeError "Module ~A has no attribute ~A" x attr.sym))))
			     
(defun py-import (mod-name mod-globals-names mod-globals-values mod-dyn-globals-ht)
  (let* ((*current-module-name* (string mod-name))
	 (file-ast (parse-python-file (format nil "~A.py" mod-name)))
	 (mod-func (compile nil `(lambda () ,file-ast)))
	 (mod-obj  (funcall mod-func)))
    (declare (special *current-module-name*))
    (loop for x across mod-globals-names and i from 0
	when (eq x mod-name)
	do (setf (svref mod-globals-values i) mod-obj)
	   (return)
	finally (setf (gethash mod-name mod-dyn-globals-ht) mod-obj))
    nil))

;; File (User object)

(defclass py-file (py-user-object py-dict-mixin)
  ((file-handle :initform nil :accessor py-file-handle))
  (:metaclass py-user-type))

(def-py-method py-file.__new__ :static (x filename)
	       (setf (py-file-handle x) (open-lisp-file-todo filename)))

(def-py-method py-file.__init__ (&rest args)
	       (declare (ignore args))
	       nil)


;; Property (User object)

(defclass py-property (py-user-object)
  ()
  (:metaclass py-user-type))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Lisp objects (proxies around Lisp values: number, string, list, tuple, dict)

(defgeneric deproxy (x)
  (:method ((x py-lisp-object))  (proxy-lisp-val x))
  (:method ((x t))               x))

(defmethod py-attr ((x py-lisp-object) attr)
  (py-attr (proxy-lisp-val x) attr))

(defmethod (setf py-attr) (val (x py-lisp-object) attr)
  (setf (py-attr (proxy-lisp-val x) attr) val))

(defmacro def-proxy-class (py-name &optional supers)
  `(progn (defclass ,py-name ,(or supers '(py-lisp-object))
	    ()
	    (:metaclass py-lisp-type))
	  (mop:finalize-inheritance (find-class ',py-name))))

;; Number (Lisp object: number)

(def-proxy-class py-number)

(def-py-method py-number.__repr__ (x^) (format nil "~A" x))

(def-py-method py-number.__eq__  (x^ y^) (py-bool (= x y)))
(def-py-method py-number.__add__ (x^ y^) (+ x y))
(def-py-method py-number.__neg__ (x^) (- x))
(def-py-method py-number.__mul__ (x^ y^) (* x y))

(def-py-method py-number.real :attribute (x^)
	       (realpart x))

(def-py-method py-number.imag :attribute (x^)
	       (imagpart x))

(def-py-method py-number.conjugate (x^)
  (conjugate x))



;; Complex

(def-proxy-class py-complex (py-number))

;; Real

(def-proxy-class py-real (py-number))


;; Integer

(def-proxy-class py-int (py-real))

(def-py-method py-int.__new__ :static (cls &optional (arg 0))
	       (if (eq cls (find-class (load-time-value 'py-int)))
		   arg
		 (let ((i (make-instance cls)))
		   (setf (proxy-lisp-val i) arg)
		   i)))

(def-py-method py-int.__init__ (&rest args) nil)

(def-py-method py-int.__floordiv__ (x^ y^)
  (values (floor x y)))

(def-py-method py-int.__mod__ (x^ y^)
  (mod x y))

(def-proxy-class py-bool (py-int))

;; Float

(def-proxy-class py-float (py-real))


;;; non-numberic classes

;; Dict

(def-proxy-class py-dict)

(defun make-dict ()
  ;; todo: (make-hash-table :test #'py-==  :hash #'py-hash)
  (make-hash-table :test #'eq))

(defmacro make-dict-unevaled-list (items)
  (let ((dict '#:dict))
    `(let ((,dict (make-dict)))
       ,@(loop for (k . v) in items
	     collect `(setf (gethash ,k ,dict) ,v))
       ,dict)))

(def-py-method py-dict.__str__ (x^)
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t)
      (format s "dict with ~A items" (hash-table-count x)))))

(def-py-method py-dict.__repr__ (x^)
  (with-output-to-string (s)
    (write-char #\{ s)
    (loop with c = (hash-table-count x)
	for key being the hash-key in x
	using (hash-value val)
	for i from 1
	do (write-string (py-repr-string key) s)
	   (write-char #\: s)
	   (write-string (py-repr-string val) s)
	   (unless (= i c)
	     (write-string ", " s)))
    (write-char #\} s)))

(def-py-method py-dict.__setitem__ (dict^ key val)
  (assert (integerp key) () "Dict: only integer keys supported for now, not: ~A" key)
  (setf (gethash key dict) val))

(def-py-method py-dict.__getitem__ (dict^ key)
  (assert (integerp key) () "Dict: only integer keys supported for now, not: ~A" key)
  (or (gethash key dict)
      (py-raise 'KeyError "Dict has no such key: ~A" key)))

(def-py-method py-dict.__iter__ (dict^)
  (with-hash-table-iterator (next-func dict)
    (make-iterator-from-function
     :name :py-dict-iterator
     :func (lambda () (multiple-value-bind (ret key val) 
			  (next-func)
			(declare (ignore val))
			(when ret key))))))

(def-py-method py-dict.__eq__ (dict^ dict2)
  (assert (eq (class-of dict2)
	      (load-time-value (find-class 'hash-table))) () "py-dict.__eq__ wants two real dicts")
  (let ((res1 (sort (loop for k being the hash-key in dict
			using (hash-value v)
			collect (cons k v))
		    #'< :key #'car))
	(res2 (sort (loop for k being the hash-key in dict2
			using (hash-value v)
			collect (cons k v))
		    #'< :key #'car)))
    
    #+(or)(warn "~A ~A" res1 res2)
    (py-bool (equalp res1 res2))))
    
  

;; List (Lisp object: adjustable array)

(def-proxy-class py-list)

(def-py-method py-list.__new__ :static (cls)
	       (if (eq cls (load-time-value (find-class 'py-list)))
		   (make-array 0 :adjustable t :fill-pointer 0)
		 (make-instance cls)))
		    
(def-py-method py-list.__init__ (x^ &optional iterable)
  (when iterable
    (loop for item in (py-iterate->lisp-list iterable)
	do (vector-push-extend item x))))

(def-py-method py-list.__str__ (x^)
  (with-output-to-string (s)
    (write-char #\[ s)
    (loop with len = (length x)
	for item across x and i from 0
	do (write-string (py-repr-string item) s)
	   (unless (= i (1- len))
	     (write-string ", " s)))
    (write-char #\] s)))

(def-py-method py-list.__len__ (x^)
  (length x))

(def-py-method py-list.__repr__ (x^)
  (with-output-to-string (s)
    (format s "[")
    (loop for item across x and i from 0
	do (unless (= i 0)
	     (format s ", "))
	   (repr-fmt s item))
    (format s "]")))

(def-py-method py-list.__iter__ (x^)
  (let ((i -1)
	(max-i (1- (length x))))
    (make-iterator-from-function
     :name :list-iterator
     :func (lambda ()
	     (when (<= (incf i) max-i)
	       (aref x i))))))

(defmacro make-py-list-unevaled-list (items)
  (let ((vec '#:vec))
    `(let ((,vec (make-array ,(length items) :adjustable t :fill-pointer ,(length items))))
       ,@(loop for x in items and i from 0
	     collect `(setf (aref ,vec ,i) ,x))
       ,vec)))

(defun make-py-list-from-list (list)
  (let* ((len (length list))
	 (vec (make-array len :adjustable t :fill-pointer t)))
    (loop for x in list and i from 0
	do (setf (aref vec i) x))
    vec))

(defun make-py-list-from-vec (vec)
  vec)

;; String (Lisp object: string)

(def-proxy-class py-string)

(def-py-method py-string.__len__ (x^)
  (length x))

(def-py-method py-string.__str__ (x^)
  x)

(def-py-method py-string.__repr__ (x^)
  (with-output-to-string (s)
    (py-pprint s x)))

(def-py-method py-string.__add__ (x^ y^)
  (concatenate 'string (the string x) (the string y)))

(def-py-method py-string.__cmp__ (x^ y^)
  (cond ((string< x y) -1)
	((string= x y)  0)
	(t              1)))

(def-py-method py-string.__mod__ (x^ args)
  (format nil "[[string-%  ~A  ~A]]" x (py-str-string args))) 
  
;; Tuple (Lisp object: consed list)

(def-proxy-class py-tuple)

(def-py-method py-tuple.__new__ :static (cls &optional iterable)
	       (let ((tup (make-tuple-from-list (when iterable
						  (py-iterate->lisp-list iterable)))))
		 
		 (cond ((eq cls (load-time-value (find-class 'py-tuple))) tup)
		       
		       ((subtypep cls (load-time-value (find-class 'py-tuple)))
			(let ((x (make-instance cls)))
			  (setf (proxy-lisp-val x) tup)
			  x))
		       
		       (t (error "invalid py-tuple.__new__ cls: ~A" cls)))))
		   

(defvar *the-empty-tuple* (make-instance 'py-tuple :lisp-object nil))

(defun make-tuple-from-list (list)
  (or list *the-empty-tuple*))

(defmacro make-tuple-unevaled-list (items)
  `(make-tuple-from-list (list ,@items)))

(def-py-method py-tuple.__repr__ (x^)
  (cond ((null x)       "()")
	((null (cdr x)) (format nil "(~/python:repr-fmt/,)" (car x)))
	(t              (format nil "(~{~/python:repr-fmt/~^, ~})" x))))

(def-py-method py-tuple.__iter__ (x^)
  (make-iterator-from-function
   :name :tuple-iterator
   :func (let ((i -1))
	   (lambda ()
	     (nth (incf i) x)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;  

(defgeneric py-class-of (x)
    (:method ((x integer)) (load-time-value (find-class 'py-int    )))
    (:method ((x real))    (load-time-value (find-class 'py-float  )))
    (:method ((x complex)) (load-time-value (find-class 'py-complex)))
    (:method ((x string))  (load-time-value (find-class 'py-string )))
    (:method ((x vector))  (load-time-value (find-class 'py-list   )))
    (:method ((x list))    (load-time-value (find-class 'py-tuple  )))
    (:method ((x hash-table)) (load-time-value (find-class 'py-dict)))
    
    (:method ((x function))    (load-time-value (find-class 'py-lisp-function)))
    (:method ((x py-function)) (load-time-value (find-class 'py-function)))
    
    (:method ((x py-lisp-type)) (load-time-value (find-class 'py-type)))
    (:method ((x py-core-type)) (load-time-value (find-class 'py-type)))
    (:method ((x py-user-type)) (load-time-value (find-class 'py-type)))
    
    (:method ((x class))   (cond
			    ((eq x (load-time-value (find-class 'py-type)))
			     x)  ;; py-type is its own class
			    
			    ((eq x (load-time-value (find-class 'py-meta-type)))
			     ;; the metatypes is posing as `type'
			     (load-time-value (find-class 'py-type)))
			    
			    ((typep x (load-time-value (find-class 'py-meta-type)))
			     ;; metatypes fake being of type `type'
			     (load-time-value (find-class 'py-type)))
			    
			    (t (class-of x))))
    (:method ((x t))       (class-of x)))

(defmethod py-attr (x attr)
  
  ;; x.a => x.__getattribute'__(x, attr).__get'__(x)
  ;; 
  ;; where the accent after xxx in __xxx'__ means that the method from
  ;; the class is used, not an instance attribute (if it would exist)
  
  (let ((ga-meth (recursive-class-lookup-and-bind x '__getattribute__)))
    
    (assert ga-meth ()
      "Object ~A (py-class: ~A) does not have a __getattribute__ method"
      x (py-class-of x))
    
    (py-call ga-meth attr)))


(defgeneric py-del-attr (x attr)
  (:documentation "Remove attribute ATTR of X")
  
  (:method (x attr)
	   (let ((da-meth (recursive-class-lookup-and-bind x '__delattr__)))
	     (assert da-meth ()
	       "Object ~A (py-class: ~A) does not have a __delattr__ method"
	       x (py-class-of x))
	     
	     (py-call da-meth attr))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Descriptors

;; The Python Reference Manual says:
;; 
;;   3.3.2.2 Implementing Descriptors
;;   
;;   In general, a descriptor is an object attribute with ``binding
;;   behavior'', one whose attribute access has been overridden by
;;   methods in the descriptor protocol: __get__(), __set__(), and
;;   __delete__().  If any of those methods are defined for an object,
;;   it is said to be a descriptor.
;; 
;; A descriptor is called a "data descriptor" iff it implements
;; `__set__'. Whether this is the case influences the attribute lookup
;; order.

(defun descriptor-p (x)
  (let ((x.class (py-class-of x)))
    (or (recursive-class-dict-lookup x.class '__get__)
	(recursive-class-dict-lookup x.class '__set__)
	(recursive-class-dict-lookup x.class '__delete__))))

(defun data-descriptor-p (x)
  "Returns DES-P, __SET__"
  ;; check for None?
  (recursive-class-dict-lookup (py-class-of x) '__set__))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Calling objects (functions, classes, instances)

(defgeneric py-call (f &rest args)
  (:method ((f t) &rest args)
	   (let ((__call__ (recursive-class-dict-lookup (py-class-of f) '__call__)))
	     (apply #'py-call __call__ f args)))
  (:method ((f function) &rest args) (apply f args)))


;;; Subscription of items (sequences, mappings)

(defgeneric py-subs (x item)
  (:method ((x t) (item t))
	   (let ((gi (recursive-class-dict-lookup (py-class-of x) '__getitem__)))
	     (if gi
		 (py-call gi x item)
	       (py-raise 'TypeError "Object ~A does not support item extraction" x)))))

(defgeneric (setf py-subs) (new-val x item)
  (:method (new-val x item)
	   (let ((si (recursive-class-dict-lookup (py-class-of x) '__setitem__)))
	     (if si
		 (py-call si x item new-val)
	       (py-raise 'TypeError "Object ~A does not support item assignment" x)))))
	  

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Math ops:  + - << ~  (etc)  and inplace variants:  += -= <<= ~=  (etc)

;; a + b   ->  (py-+ a b)   ->  a.__add__(b) or b.__radd__(a)
;; 
;; x += y  ->  (py-+= x y)  ->  x.__iadd__(y)
;;                              fallback: x = x.__add__(y)
;; 
;; The fall-back is not part of the py-+= function, because it
;; operates on /places/, while the function only tries the in-place
;; operation on a /value/.
;; 
;; The return value of py-+= indicates whether the in-place method
;; __iadd__ was found.

(defun raise-invalid-operands (operation left &optional right)
  ;; XXX merge into one pretty printer string
  ;; XXX TypeError
  (error (if right
	     (format nil "Operation '~A' not supported for operands ~S and ~S."
		     operation left right)
	   (format nil "Operation '~S' not supported for operand ~S." operation left))))

(defvar *binary-op-funcs-ht* (make-hash-table :test #'eq))
(defvar *binary-iop-funcs-ht* (make-hash-table :test #'eq))
(defvar *binary-iop->op-ht* (make-hash-table :test #'eq))


  
(defun get-binary-op-func-name (op) (or (gethash op *binary-op-funcs-ht*)
				   (error "missing binary op func: ~A" op)))
(defun get-binary-iop-func-name (iop) (or (gethash iop *binary-iop-funcs-ht*)
				     (error "missing binary iop func: ~A" iop)))
(defun get-binary-op-func-name-from-iop (iop)
  (let ((op (or (gethash iop *binary-iop->op-ht*)
		(error "IOP ~S has no OP counterpart" iop))))
    (get-binary-op-func-name op)))
  
(defmacro def-math-func (op-syntax op-func l-meth r-meth iop-syntax iop-func i-meth)
  `(progn
     
     (defgeneric ,op-func (x y)
       (:method ((x t) (y t))
		(let* ((x.class (py-class-of x))
		       (y.class (py-class-of y))
		       (y-sub-of-x (and (not (eq x.class y.class))
					(subtypep y.class x.class))))
		  
		  (loop
		      with try-right = y-sub-of-x
		      with finish = nil
		      do (let* ((op-meth (recursive-class-dict-lookup
					  (if try-right y.class x.class)
					  (if try-right ',r-meth ',l-meth)))
				(res (and op-meth 
					  (py-call op-meth
						   (if try-right y x)
						   (if try-right x y)))))
			   (when res
			     (unless (eq res (load-time-value *the-notimplemented*))
			       (return res))))
			 
			 (if finish
			     (raise-invalid-operands ',op-syntax x y)
			   (setf try-right (not try-right)
				 finish t))))))
     
     ,(when op-syntax
	`(setf (gethash ',op-syntax *binary-op-funcs-ht*) ',op-func))
     
     ,(when iop-func
	`(defgeneric ,iop-func (x val)
	   (:method ((x t) (val t))
		    (let* ((iop-meth (recursive-class-dict-lookup (py-class-of x) ',i-meth))
			   (res (and iop-meth 
				     (py-call iop-meth x val))))
		      (and iop-meth
			   (not (eq res (load-time-value *the-notimplemented*))))))))
     
     ,(when iop-syntax
	`(setf (gethash ',iop-syntax *binary-iop-funcs-ht*) ',iop-func))
     
     ,(when (and iop-syntax op-syntax)
	`(setf (gethash ',iop-syntax *binary-iop->op-ht*) ',op-syntax))))


;; /t/ is not Python syntax, but a hack to support __future__ feature
;; `true division'
(def-math-func +   py-+    __add__      __radd__       +=   py-+=   __iadd__      )
(def-math-func -   py--    __sub__      __rsub__       -=   py--=   __isub__      )
(def-math-func *   py-*    __mul__      __rmul__       *=   py-*=   __imul__      )
(def-math-func /t/ py-/t/  __truediv__  __rtruediv__   /t/  py-/t/= __itruediv__  )
(def-math-func //  py-//   __floordiv__ __rfloordiv__  //=  py-//=  __ifloordiv__ ) 
(def-math-func /   py-/    __div__      __rdiv__       /=   py-/=   __idiv__      )
(def-math-func %   py-%    __mod__      __rmod__       %=   py-%=   __imod__      )
(def-math-func <<  py-<<   __lshift__   __rlshift__    <<=  py-<<=  __ilshift__   )
(def-math-func >>  py->>   __rshift__   __rrshift__    >>=  py->>=  __irshift__   )
(def-math-func &   py-&    __and__      __rand__       &=   py-&=   __iand__      )
(def-math-func \|  py-\|   __or__       __ror__        \|=  py-\|=  __ior__       )
(def-math-func ^   py-^    __xor__      __rxor__       ^=   py-^=   __ixor__      )
(def-math-func nil py-divmod __divmod__ __rdivmod__    nil  nil     nil           )

;; a**b (to-the-power) is a special case:
;;   
;; - method __pow__ takes an optional third argument: the c in
;;   (a**b)%c that argument can be supplied using the built-in
;;   function POW, but not syntactically using **
;;  
;; - there are no __rpow__ methods
;;   
;; - so, this function py-** always gets 2 arguments when called for
;;   the a**b syntax, but may have a third argument when called for
;;   the built-in function POW.

(defun py-** (x y &optional z)
  (let* ((x.class (py-class-of x))
	 (op-meth (recursive-class-dict-lookup x.class '__pow__))
	 (res (and op-meth (if z
			       (py-call op-meth x y z)
			     (py-call op-meth x y)))))
    
    (if (and res (not (eq res (load-time-value *the-notimplemented*))))
	res
      (raise-invalid-operands '** x y))))

(setf (gethash '** *binary-op-funcs-ht*) 'py-**)

;; **= has similar ugliness

(defun py-**= (x y &optional z)
  (let* ((x.class (py-class-of x))
	 (iop-meth (recursive-class-dict-lookup x.class '__ipow__))
	 (res (and iop-meth (if z
				(py-call iop-meth x y z)
			      (py-call iop-meth x y)))))
    
    (if (and iop-meth (not (eq res (load-time-value *the-notimplemented*))))
	res
      nil)))

(setf (gethash '**= *binary-iop-funcs-ht*) 'py-**=)


(defvar *unary-op-funcs-ht* (make-hash-table :test #'eq))
(defun get-unary-op-func-name (op) (or (gethash op *unary-op-funcs-ht*)
				  (error "missing unary op func: ~A" op)))

(defmacro def-unary-op-func (syntax fname meth)
  `(progn (defgeneric ,fname (x)
	    (:method ((x t))
		     (let* ((x.class (py-class-of x))
			    (op-meth (recursive-class-dict-lookup x.class ',meth))
			    (res (and op-meth (py-call op-meth x))))
		       (if (or (null op-meth)
			       (eq res (load-time-value *the-notimplemented*)))
			   (raise-invalid-operands ',syntax x)
			 res))))
	  (setf (gethash ',syntax *unary-op-funcs-ht*) ',fname)))

(def-unary-op-func ~  py-unary-~  __invert__ )
(def-unary-op-func +  py-unary-+  __pos__    )
(def-unary-op-func -  py-unary--  __neg__    )

(defgeneric py-not (x)
  (:method ((x t))
	   (py-bool (not (py-val->lisp-bool x)))))

(setf (gethash 'not *unary-op-funcs-ht*) 'py-not)

;; Equality and membership testing:  a in b, a not in b, a is b, a is not b

(defvar *binary-test-funcs-ht* (make-hash-table :test #'eq))
(defun get-binary-test-func (op) (or (gethash op *binary-test-funcs-ht*)
				     (error "missing binary test func: ~A" op)))

(defgeneric py-in (x seq)
  (:method ((x t) (seq t))
	   ;; use __contains__, fall back on iterator
	   (let ((contains-meth (recursive-class-dict-lookup
				 (py-class-of seq) '__contains__)))
	     (if contains-meth
		 (let ((res (py-call contains-meth seq x)))
		   (cond ((eq res t)   (load-time-value *the-true*))
			 ((eq res nil) (load-time-value *the-false*))
			 (t            res)))
	       (loop with f = (get-py-iterate-fun seq)
		   for seq-item = (funcall f)
		   while seq-item
		   when (py-val->lisp-bool (py-== x seq-item))
		   return (load-time-value *the-true*)
		   finally (return (load-time-value *the-false*)))))))
	     
(defgeneric py-not-in (x seq)
  (:method ((x t) (seq t))
	   (py-not (py-in x seq))))

(setf (gethash 'in *binary-op-funcs-ht*) 'py-in)
(setf (gethash '|not in| *binary-op-funcs-ht*) 'py-not-in)

(defgeneric py-is (x y)
  (:method ((x t) (y t))
	   (if (eq x y) *the-true* *the-false*)))

(defgeneric py-is-not (x y)
  (:method ((x t) (y t))
	   (if (eq x y) *the-false* *the-true*)))

(setf (gethash 'is *binary-op-funcs-ht*) 'py-is)
(setf (gethash '|is not| *binary-op-funcs-ht*) 'py-is-not)



;; Binary comparison operations
;; 
;; It appears that all comparisons -- < > <= >= == != <> -- are
;; defined in terms of the outcome of built-in function `cmp'
;; (#'py-cmp).
;; 
;; #'py-< implements the logic for "a < b"
;; 
;; Note this important point: "a < b" is NOT directly translated into
;; a.__lt__(b), although this __lt__ method *might* be called by
;; __cmp__, as might b.__ge__ in this case.
;; 
;;  '<  -->  #'py-<
;; 
;; This mapping is used by the interpreter, in EVAL-COMPARISON
;; (pyeval.cl).

(defvar *binary-comparison-funcs-ht* (make-hash-table :test #'eq))
(defun get-binary-comparison-func-name (op) (gethash op *binary-comparison-funcs-ht*))

(defmacro def-comparison (syntax func test-x-y)
  `(progn (defgeneric ,func (x y)
	    (:method ((x t) (y t))
		     #+(or)(declare (optimize (speed 3) (safety 1) (debug 0)))
		     (if ,test-x-y
			 (load-time-value *the-true*)
		       (load-time-value *the-false*))))
	  (setf (gethash ',syntax *binary-comparison-funcs-ht*) ',func)))
	    
;; pyb:cmp returns -1, 0 or 1 (or TypeError if user-supplied
;; method returns bogus comparison result; that TypeError is not
;; catched here but goes to user code.)

(def-comparison  <  py-<   (=  (the (integer -1 1) (pybf:cmp x y)) -1))
(def-comparison  >  py->   (=  (the (integer -1 1) (pybf:cmp x y))  1))
(def-comparison ==  py-==  (=  (the (integer -1 1) (pybf:cmp x y))  0))
(def-comparison !=  py-!=  (/= (the (integer -1 1) (pybf:cmp x y))  0)) ;; parser: <> -> !=
(def-comparison <=  py-<=  (<= (the (integer -1 1) (pybf:cmp x y))  0))
(def-comparison >=  py->=  (>= (the (integer -1 1) (pybf:cmp x y))  0))


(defgeneric py-val->lisp-bool (x)
  (:method ((x number)) (/= x 0)))


;; Shortcut functions

(defmacro def-py-shortcut-func (funcname method &key error)
  `(defgeneric ,funcname (x)
     (:method ((x t)) (let* ((x.cls (py-class-of x))
			     (,method (recursive-class-dict-lookup x.cls ',method)))
			(if ,method
			    (py-call ,method x)
			  ,(or error
			       `(py-raise 'TypeError
					  "Object ~A (a ~A) has no `~A' method"
					  x (class-name (py-class-of x)) ,(symbol-name method))))))))

(def-py-shortcut-func py-abs  __abs__ )
(def-py-shortcut-func py-repr __repr__)
(def-py-shortcut-func py-str  __str__ :error (py-repr x))
(def-py-shortcut-func py-hash __hash__)
(def-py-shortcut-func py-hex  __hex__ )
(def-py-shortcut-func py-oct  __oct__ )
(def-py-shortcut-func py-len  __len__ )

(defun py-val->string (x)
  (let ((s (deproxy x))) ;; deproxy, as it may be py-string subclass instance
    (if (stringp s)
	s
      (py-raise 'TypeError "Expected a string, but got: ~A" x))))

(defun py-repr-string (x) (py-val->string (py-repr x)))
(defun py-str-string  (x) (py-val->string (py-str x)))

(defun py-str-symbol  (x &optional (package #.*package*))
  (if (symbolp x) 
      x
    (intern (py-str-string x) package)))


(defun repr-fmt (stream argument &optional colon-p at-p &rest parameters)
  "Wrapper function for PY-REPR that is usable inside format string, using
the ~/.../ directive: ~/python:repr-fmt/"
  
  (when (or colon-p at-p parameters)
    (error "Format string function py-repr-fmt does not support colon, ~
            at or parameters"))
  
  (let ((s (py-repr-string argument)))
    (write-string s stream)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Iteration

;; iterator from lambda

(defclass py-func-iterator (py-core-object)
  ((name        :initarg :name)
   (func        :initarg :func :type function)
   (stopped-yet :initform nil))
  (:metaclass py-core-type))

(defun make-iterator-from-function (&key func name)
  "Create an iterator that calls f again and again. F somehow has
to keep its own state. As soon as F returns NIL, it is considered
finished; F will then not be called again."
  (check-type func function)
  (make-instance 'py-func-iterator :func func :name name))

(def-py-method py-func-iterator.next (fi)
  (with-slots (stopped-yet func) fi
    (let ((res (cond (stopped-yet nil)
		     ((funcall func))
		     (t (setf stopped-yet t)
			nil))))
      (if res
	  (return-from py-func-iterator.next res)
	(py-raise 'StopIteration "Iterator ~S has finished" fi)))))

(def-py-method py-func-iterator.__repr__ (fi)
  (with-output-to-string (s)
    (print-unreadable-object (fi s :identity t)
      (with-slots (name) fi
	(format s "generator ~@[~A~]" name)))))

(def-py-method py-func-iterator.__iter__ (f)
  f)

;; general useful iteration constructs

(defgeneric get-py-iterate-fun (x)
  (:documentation
   "Return a function that when called repeatedly returns VAL, T, where VAL is the
next value gotten by iterating over X. Returns NIL, NIL upon exhaustion.")
  (:method ((x t))
	   (let* ((x.cls       (py-class-of x))
		  (__iter__    (recursive-class-dict-lookup x.cls '__iter__))
		  (__getitem__ (and (not __iter__)
				    (recursive-class-dict-lookup x.cls '__getitem__))))

	     ;; TODO: binding __getitem__ using __get__ is not done at
	     ;; all yet.
	     
	     (cond (__iter__ ;; Preferable, use __iter__ to retrieve x's iterator
		    (let* ((iterator     (py-call __iter__ x))
			   (iterator.cls (py-class-of iterator))
			   (next-meth    (or (recursive-class-dict-lookup iterator.cls 'next)
					     (py-raise
					      'TypeError
					      "The value returned by ~A's `__iter__' method ~
                  		               is ~A, which is not an iterator (no `next' method)"
					      x iterator))))
		      
		      ;; Note that we just looked up the `next' method
		      ;; before the first value is demanded. This is
		      ;; semantically incorrect in an ignorable way.
		      
		      (excl:named-function (:py-iterate-fun using __iter__)
			(lambda ()
			  (handler-case (values (py-call next-meth iterator))
			    (StopIteration () (values nil nil))
			    (:no-error (val)  (values val t)))))))
		   
		   
		   (__getitem__ ;; Fall-back: call __getitem__ with successive integers
		    (let ((index 0))
		      (excl:named-function (:py-iterate-fun using __getitem__)
			(lambda ()
			  (handler-case (values (py-call __getitem__ x index))
			    
			    ;; ok if this happens when index = 0: then it's an empty sequence
			    (IndexError () (values nil nil)) 
			    
			    (:no-error (val) (progn (incf index)
						    (values val t))))))))
		   
		   (t
		    (py-raise 'TypeError "Iteration over non-sequence (got: ~A)" x))))))

(defgeneric map-over-py-object (func object)
  (:documentation 
   "Iterate over OBJECT, calling the Lisp function FUNC on each value. Returns nothing.")
  
  (:method ((func function) (object t))
	   (break "map over ~A" object)
	   (loop with it-fun = (get-py-iterate-fun object)
	       for val = (funcall it-fun)
	       while val do (funcall func val))))


(defgeneric py-iterate->lisp-list (object)
  (:documentation
   "Returns a Lisp list, that may not be modified destructively.")
  (:method ((x t))
	   (loop with it-fun = (get-py-iterate-fun x)
	       for val = (funcall it-fun)
	       while val collect val)))



(defun get-py-iterator-for-object (x)
  (let* ((x.cls       (py-class-of x))
	 (__iter__    (recursive-class-dict-lookup x.cls '__iter__)))
    
    (if __iter__
	
	(py-call __iter__ x)
      
      (let ((f (get-py-iterate-fun x)))
	(make-iterator-from-function f)))))


(defun py-print (dest items comma?)
  (when dest
    (warn "ignoring 'dest' arg of PRINT stmt (got: ~A)" dest))
  
  (excl::fast
   (let ((*print-pretty* nil))
     (dolist (x items)
       (typecase x
	 (integer (excl::fast (write (the integer x) :base 10)))
	 (t (format t "~A " (py-str-string x))))
       (write-char #\Space t))
     
     (unless comma?
       (write-char #\Newline)))))


